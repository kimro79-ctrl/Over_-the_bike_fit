import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 스플래시 화면 지연 시간
  await Future.delayed(const Duration(seconds: 4));
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
  Timer? _workoutTimer;
  Timer? _watchDataTimer;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false;
  List<FlSpot> _hrSpots = [];
  double _timerCounter = 0;

  // [워치 연결 기능] - 권한 이동 및 데이터 수신 활성화
  Future<void> _handleWatchConnection() async {
    await [Permission.bluetoothConnect, Permission.bluetoothScan, Permission.location].request();
    await openAppSettings(); 

    setState(() {
      _isWatchConnected = true;
      _heartRate = 72; // 연결 직후 초기값
    });

    // 👈 워치 연결 시에만 작동하는 데이터 스트림
    _watchDataTimer?.cancel();
    _watchDataTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted || !_isWatchConnected) { t.cancel(); return; }
      setState(() {
        if (_isWorkingOut) {
          _heartRate = 95 + Random().nextInt(40);
          _hrSpots.add(FlSpot(_timerCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 40) _hrSpots.removeAt(0);
          _timerCounter += 0.5;
          _calories += 0.05;
        } else {
          _heartRate = 65 + Random().nextInt(10);
        }
      });
    });
  }

  // [운동 시작 기능] - 워치 연결 없이도 독립 작동
  void _toggleWorkout() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() { _duration += const Duration(seconds: 1); });
        });
      } else {
        _workoutTimer?.cancel();
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
                const SizedBox(height: 10),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white54)),
                
                // 워치 연결 버튼
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ActionChip(
                    avatar: Icon(Icons.bluetooth, size: 14, color: _isWatchConnected ? Colors.cyanAccent : Colors.white),
                    label: Text(_isWatchConnected ? "워치 데이터 동기화 중" : "권한 설정 및 워치 연결", style: const TextStyle(fontSize: 11)),
                    onPressed: _handleWatchConnection,
                    backgroundColor: Colors.black.withOpacity(0.6),
                  ),
                ),

                // 그래프: 워치 연결 시에만 노출
                Container(
                  height: MediaQuery.of(context).size.height * 0.12,
                  margin: const EdgeInsets.symmetric(horizontal: 50),
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(10)),
                  child: LineChart(LineChartData(
                    minY: 60, maxY: 160,
                    lineBarsData: [LineChartBarData(
                      spots: _isWatchConnected && _hrSpots.isNotEmpty ? _hrSpots : [const FlSpot(0, 0)],
                      isCurved: true, 
                      color: Colors.cyanAccent.withOpacity(_isWatchConnected ? 0.8 : 0.0),
                      barWidth: 1.5,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: _isWatchConnected, color: Colors.cyanAccent.withOpacity(0.1))
                    )],
                    titlesData: const FlTitlesData(show: false),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                  )),
                ),

                const Spacer(),

                // 수치 데이터 타일
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 50),
                  child: GridView.count(
                    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2, childAspectRatio: 3.5,
                    children: [
                      _tile('심박수', _isWatchConnected ? '$_heartRate BPM' : '--', Icons.favorite, Colors.redAccent),
                      _tile('칼로리', '${_calories.toStringAsFixed(1)} kcal', Icons.local_fire_department, Colors.orangeAccent),
                      _tile('운동 시간', _formatDuration(_duration), Icons.timer, Colors.blueAccent),
                      _tile('상태', _isWorkingOut ? '운동중' : '대기', Icons.bolt, Colors.amberAccent),
                    ],
                  ),
                ),

                // 하단 버튼
                Padding(
                  padding: const EdgeInsets.only(bottom: 30, top: 15),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _btn(_isWorkingOut ? '정지' : '시작', _isWorkingOut ? Icons.stop : Icons.play_arrow, _toggleWorkout),
                      _btn('저장', Icons.save, () {}),
                      _btn('기록 보기', Icons.history, () {}),
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

  Widget _tile(String l, String v, IconData i, Color c) => Column(children: [
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, color: c, size: 10), const SizedBox(width: 4), Text(l, style: const TextStyle(fontSize: 9, color: Colors.white38))]),
    Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
  ]);

  Widget _btn(String l, IconData i, VoidCallback t) => InkWell(onTap: t, child: Container(
    width: 85, height: 48,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: const LinearGradient(colors: [Color(0xFF333333), Color(0xFF000000)]), border: Border.all(color: Colors.white10)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, size: 14, color: Colors.white), Text(l, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))]),
  ));

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
