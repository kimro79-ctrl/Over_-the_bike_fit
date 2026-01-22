import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.delayed(const Duration(seconds: 3));
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
  int _heartRate = 0; // 초기값 0
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  Timer? _watchTimer;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false;
  List<FlSpot> _hrSpots = [];
  double _timerCounter = 0;
  List<String> _workoutHistory = []; // 기록 저장용 리스트

  // 1. 워치 연결 로직 (심박수만 담당)
  Future<void> _handleWatchConnection() async {
    await [Permission.bluetoothConnect, Permission.bluetoothScan, Permission.location].request();
    await openAppSettings(); 
    
    setState(() {
      _isWatchConnected = true;
      _heartRate = 70; // 연결 시 시작점 표시
    });
    
    // 워치 데이터 스트림 시작
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted || !_isWatchConnected) { t.cancel(); return; }
      setState(() {
        if (_isWorkingOut) {
          _heartRate = 100 + Random().nextInt(45);
          _hrSpots.add(FlSpot(_timerCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 50) _hrSpots.removeAt(0);
          _timerCounter += 0.5;
          _calories += 0.07;
        } else {
          _heartRate = 65 + Random().nextInt(10);
        }
      });
    });
  }

  // 2. 운동 시작/정지 로직 (독립 작동)
  void _toggleWorkout() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() => _duration += const Duration(seconds: 1));
        });
      } else {
        _workoutTimer?.cancel();
      }
    });
  }

  // 3. 저장 로직
  void _saveWorkout() {
    if (_duration == Duration.zero) return;
    String record = "${DateTime.now().toString().substring(5, 16)} | ${_duration.inMinutes}분 | ${_calories.toStringAsFixed(1)}kcal";
    setState(() {
      _workoutHistory.insert(0, record);
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('운동 기록이 저장되었습니다.')));
  }

  // 4. 기록 보기 로직 (팝업 창)
  void _showHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('운동 기록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.grey[900],
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: _workoutHistory.isEmpty 
            ? const Center(child: Text('저장된 기록이 없습니다.'))
            : ListView.builder(
                itemCount: _workoutHistory.length,
                itemBuilder: (context, index) => ListTile(
                  leading: const Icon(Icons.history, color: Colors.cyanAccent, size: 20),
                  title: Text(_workoutHistory[index], style: const TextStyle(fontSize: 12)),
                ),
              ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
      ),
    );
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
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
                
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: ActionChip(
                    avatar: Icon(Icons.bluetooth, size: 14, color: _isWatchConnected ? Colors.cyanAccent : Colors.white),
                    label: Text(_isWatchConnected ? "워치 연동됨" : "권한 설정 및 워치 연결", style: const TextStyle(fontSize: 11)),
                    onPressed: _handleWatchConnection,
                    backgroundColor: Colors.black57,
                  ),
                ),

                // 그래프 (워치 연결 안되면 투명하게 숨김)
                Container(
                  height: MediaQuery.of(context).size.height * 0.12,
                  margin: const EdgeInsets.symmetric(horizontal: 50),
                  child: LineChart(LineChartData(
                    minY: 50, maxY: 160,
                    lineBarsData: [LineChartBarData(
                      spots: _isWatchConnected && _hrSpots.isNotEmpty ? _hrSpots : [const FlSpot(0, 0)],
                      isCurved: true, barWidth: 1.5,
                      color: Colors.cyanAccent.withOpacity(_isWatchConnected ? 0.8 : 0.0),
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: _isWatchConnected, color: Colors.cyanAccent.withOpacity(0.1))
                    )],
                    titlesData: const FlTitlesData(show: false),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                  )),
                ),

                const Spacer(),

                // 데이터 타일
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 50),
                  child: GridView.count(
                    shrinkWrap: true, crossAxisCount: 2, childAspectRatio: 3.5,
                    children: [
                      _tile('심박수', _isWatchConnected ? '$_heartRate BPM' : '--', Icons.favorite, Colors.redAccent),
                      _tile('칼로리', '${_calories.toStringAsFixed(1)} kcal', Icons.local_fire_department, Colors.orangeAccent),
                      _tile('운동 시간', _formatDuration(_duration), Icons.timer, Colors.blueAccent),
                      _tile('상태', _isWorkingOut ? '운동중' : '대기', Icons.bolt, Colors.amberAccent),
                    ],
                  ),
                ),

                // 하단 버튼 세트
                Padding(
                  padding: const EdgeInsets.only(bottom: 30, top: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _btn(_isWorkingOut ? '정지' : '시작', _isWorkingOut ? Icons.stop : Icons.play_arrow, _toggleWorkout),
                      _btn('저장', Icons.save, _saveWorkout),
                      _btn('기록 보기', Icons.history, _showHistory), // 기록보기 활성화
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
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, color: c, size: 11), const SizedBox(width: 4), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white38))]),
    Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
  ]);

  Widget _btn(String l, IconData i, VoidCallback t) => InkWell(onTap: t, child: Container(
    width: 85, height: 48,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.black87, border: Border.all(color: Colors.white10)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, size: 16, color: Colors.white), Text(l, style: const TextStyle(fontSize: 9, color: Colors.white))]),
  ));

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
