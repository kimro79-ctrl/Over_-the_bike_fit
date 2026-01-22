import 'dart:async';
import 'dart:math'; // 👈 이게 빠져서 에러가 났었습니다. 추가 완료!
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

  // 워치 연결 버튼 누를 시 권한 요청 및 설정 이동
  Future<void> _handlePermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    // 권한이 하나라도 영구 거부된 경우 설정창으로 이동
    if (statuses.values.any((s) => s.isPermanentlyDenied)) {
      openAppSettings();
    } else {
      _startSimulatedData();
    }
  }

  void _startSimulatedData() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('스마트워치 데이터 동기화 시작'), duration: Duration(seconds: 1))
    );
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) t.cancel();
      setState(() {
        _heartRate = 65 + Random().nextInt(40); // 65~105 사이 랜덤 심박수
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
          // 배경 이미지
          Positioned.fill(child: Image.asset('assets/background.png', fit: BoxFit.cover, 
            errorBuilder: (_,__,___) => Container(color: Colors.black))),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text('Over The Bike Fit', 
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Colors.white)),
                
                // 1. 워치 연결 버튼 (텍스트 바로 아래)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: OutlinedButton.icon(
                    onPressed: _handlePermissions,
                    icon: const Icon(Icons.watch, size: 18, color: Colors.blueAccent),
                    label: const Text("워치 연결 및 권한 설정", style: TextStyle(color: Colors.white70)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
                  ),
                ),

                // 2. 그래프 (전체 높이의 1/3 정도로 축소)
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.22,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
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

                // 3. 데이터 표시 (50% 축소 디자인)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: GridView.count(
                      crossAxisCount: 2,
                      childAspectRatio: 2.2,
                      children: [
                        _smallTile('심박수', '$_heartRate BPM', Icons.favorite, Colors.red),
                        _smallTile('소모 칼로리', '${_calories.toStringAsFixed(1)} kcal', Icons.local_fire_department, Colors.orange),
                        _smallTile('운동 시간', _formatDuration(_duration), Icons.timer, Colors.blue),
                        _smallTile('상태', _heartRate >= 90 ? '고강도' : '저강도', Icons.speed, Colors.green),
                      ],
                    ),
                  ),
                ),

                // 4. 블랙 그라데이션 버튼 (시작/저장/기록 보기)
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _gradButton(_isWorkingOut ? '정지' : '시작', _isWorkingOut ? Icons.stop : Icons.play_arrow, _toggleWorkout),
                      _gradButton('저장', Icons.save, () {}),
                      _gradButton('운동기록 보기', Icons.history, () {}),
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

  Widget _smallTile(String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _gradButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 105,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: const LinearGradient(
            colors: [Color(0xFF333333), Color(0xFF000000)], // 블랙 그라데이션
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: Colors.white),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
