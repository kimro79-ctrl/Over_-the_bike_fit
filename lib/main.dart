import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BikeFitApp());
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: const WorkoutScreen(),
    );
  }
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override
  _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0;
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _timer;
  bool _isWorkingOut = false;
  List<FlSpot> _hrSpots = [];
  double _timerCounter = 0;

  // 권한 요청 및 설정창 이동
  Future<void> _handlePermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    if (statuses.values.any((status) => status.isPermanentlyDenied)) {
      openAppSettings(); // 영구 거절 시 설정으로 이동
    } else {
      _startSimulatedData(); // 권한 허용 시 데이터 시작
    }
  }

  void _startSimulatedData() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('워치 데이터를 동기화합니다.')));
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) t.cancel();
      setState(() {
        _heartRate = 60 + (DateTime.now().second % 60) + (Random().nextInt(20)); 
        if (_isWorkingOut) {
          _hrSpots.add(FlSpot(_timerCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 30) _hrSpots.removeAt(0);
          if (_heartRate >= 90) _calories += 0.05;
        }
      });
    });
  }

  void _toggleWorkout() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() { _duration += const Duration(seconds: 1); _timerCounter++; });
        });
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/background.png', fit: BoxFit.cover, 
            errorBuilder: (_,__,___) => Container(color: Colors.black))),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 15),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                
                // 1. 워치 연결 버튼 (텍스트 바로 아래 배치)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: InkWell(
                    onTap: _handlePermissions,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [Icon(Icons.watch, size: 18), SizedBox(width: 8), Text("워치 연결 및 권한 설정")],
                      ),
                    ),
                  ),
                ),

                // 2. 그래프 섹션 (3/1 정도로 축소)
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.22,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    child: LineChart(LineChartData(
                      lineBarsData: [LineChartBarData(
                        spots: _hrSpots, isCurved: true, color: Colors.redAccent, 
                        barWidth: 3, dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(show: true, color: Colors.redAccent.withOpacity(0.1))
                      )],
                      titlesData: const FlTitlesData(show: false),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                    )),
                  ),
                ),

                // 3. 데이터 섹션 (크기 50% 축소 및 밀집도 향상)
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    childAspectRatio: 2.0,
                    children: [
                      _smallDataTile('심박수', '$_heartRate BPM', Icons.favorite, Colors.red),
                      _smallDataTile('소모 칼로리', '${_calories.toStringAsFixed(1)} kcal', Icons.local_fire_department, Colors.orange),
                      _smallDataTile('운동 시간', _formatDuration(_duration), Icons.timer, Colors.blue),
                      _smallDataTile('상태', _heartRate >= 90 ? '고강도' : '저강도', Icons.speed, Colors.green),
                    ],
                  ),
                ),

                // 4. 블랙 그라데이션 버튼 세트
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _gradButton(_isWorkingOut ? '정지' : '시작', _isWorkingOut ? Icons.stop : Icons.play_arrow, _toggleWorkout),
                      _gradButton('저장', Icons.save, () {}),
                      _gradButton('기록 보기', Icons.history, () {}),
                    ],
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _smallDataTile(String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _gradButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [Color(0xFF2C2C2C), Color(0xFF000000)], // 블랙 그라데이션
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 5, offset: const Offset(0, 3))],
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: Colors.white),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
// Random 클래스 사용을 위해 최상단에 import 'dart:math'; 추가 필요
