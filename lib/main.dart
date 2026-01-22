import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 스플래시 화면 지연 시간 2초로 수정
  await Future.delayed(const Duration(seconds: 2));
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
  Timer? _watchTimer;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false; // 실제 연결 여부 플래그
  List<FlSpot> _hrSpots = [];
  double _timerCounter = 0;
  List<String> _workoutHistory = [];

  // 워치 연결 시뮬레이션 (권한 허용 후 '실제' 연결 상태로 전환)
  Future<void> _handleWatchConnection() async {
    // 1. 권한 체크
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    if (statuses.values.every((status) => status.isGranted)) {
      // 2. 권한이 모두 허용된 경우에만 연결 프로세스 시작
      setState(() {
        _isWatchConnected = true; // 실제 연결됨으로 표시
        _heartRate = 72; // 초기 심박수 설정
      });
      
      _startHeartRateMonitoring();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('워치와 성공적으로 연결되었습니다.'))
      );
    } else {
      // 권한 거부 시 설정창 이동 유도
      await openAppSettings();
    }
  }

  // 심박수 모니터링 로직 (연결된 상태에서만 작동)
  void _startHeartRateMonitoring() {
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(const Duration(milliseconds: 200), (t) { // 더 디테일한 데이터 (0.2초 단위)
      if (!mounted || !_isWatchConnected) {
        t.cancel();
        return;
      }
      
      setState(() {
        if (_isWorkingOut) {
          // 운동 중일 때: 더 역동적인 심박 변화와 디테일한 그래프 점 추가
          _heartRate = 120 + Random().nextInt(30); 
          _timerCounter += 0.2;
          _hrSpots.add(FlSpot(_timerCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 100) _hrSpots.removeAt(0); // 더 긴 데이터 유지
          _calories += 0.02;
        } else {
          // 대기 중일 때: 안정적인 심박수 유지
          _heartRate = 65 + Random().nextInt(10);
        }
      });
    });
  }

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

  void _saveWorkout() {
    if (_duration.inSeconds < 1) return;
    String record = "${DateTime.now().toString().substring(5, 16)} | ${_duration.inMinutes}분 | ${_calories.toStringAsFixed(1)}kcal";
    setState(() => _workoutHistory.insert(0, record));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('운동 데이터가 저장되었습니다.')));
  }

  void _showHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('운동 기록 히스토리'),
        backgroundColor: Colors.black87,
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: _workoutHistory.isEmpty 
            ? const Center(child: Text('저장된 기록이 없습니다.'))
            : ListView.builder(
                itemCount: _workoutHistory.length,
                itemBuilder: (context, index) => ListTile(
                  leading: const Icon(Icons.fitness_center, color: Colors.cyanAccent),
                  title: Text(_workoutHistory[index], style: const TextStyle(fontSize: 13)),
                  dense: true,
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
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: ActionChip(
                    avatar: Icon(Icons.bluetooth, size: 16, color: _isWatchConnected ? Colors.cyanAccent : Colors.white54),
                    label: Text(_isWatchConnected ? "워치 데이터 동기화 중" : "권한 설정 및 워치 연결"),
                    onPressed: _isWatchConnected ? null : _handleWatchConnection,
                    backgroundColor: Colors.black45,
                  ),
                ),

                // 디테일한 실시간 그래프
                Container(
                  height: 140,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: LineChart(LineChartData(
                    minY: 50, maxY: 180,
                    lineBarsData: [LineChartBarData(
                      spots: _isWatchConnected && _hrSpots.isNotEmpty ? _hrSpots : [const FlSpot(0, 0)],
                      isCurved: true, 
                      curveRadius: 0.5,
                      barWidth: 3, 
                      color: Colors.cyanAccent.withOpacity(_isWatchConnected ? 1.0 : 0.0),
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: _isWatchConnected, 
                        color: Colors.cyanAccent.withOpacity(0.15)
                      )
                    )],
                    titlesData: const FlTitlesData(show: false),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                  )),
                ),

                const Spacer(),

                // 운동 데이터 영역
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(30)
                  ),
                  child: GridView.count(
                    shrinkWrap: true, crossAxisCount: 2, childAspectRatio: 2.5,
                    children: [
                      _tile('심박수', _isWatchConnected ? '$_heartRate BPM' : '--', Icons.favorite, Colors.redAccent),
                      _tile('칼로리', '${_calories.toStringAsFixed(1)} kcal', Icons.local_fire_department, Colors.orangeAccent),
                      _tile('운동 시간', _formatDuration(_duration), Icons.timer, Colors.blueAccent),
                      _tile('상태', _isWorkingOut ? '운동 중' : '대기', Icons.bolt, Colors.amberAccent),
                    ],
                  ),
                ),

                // 하단 버튼
                Padding(
                  padding: const EdgeInsets.only(bottom: 40, top: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _btn(_isWorkingOut ? '정지' : '시작', _isWorkingOut ? Icons.stop : Icons.play_arrow, _toggleWorkout),
                      _btn('저장', Icons.save, _saveWorkout),
                      _btn('기록 보기', Icons.history, _showHistory),
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

  Widget _tile(String l, String v, IconData i, Color c) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, color: c, size: 14), const SizedBox(width: 6), Text(l, style: const TextStyle(fontSize: 11, color: Colors.white70))]),
      const SizedBox(height: 4),
      Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
  ]);

  Widget _btn(String l, IconData i, VoidCallback t) => InkWell(
    onTap: t, 
    borderRadius: BorderRadius.circular(15),
    child: Container(
      width: 100, height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15), 
        color: Colors.black87, 
        border: Border.all(color: Colors.white12)
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, size: 22, color: Colors.white), const SizedBox(height: 4), Text(l, style: const TextStyle(fontSize: 11, color: Colors.white))]),
  ));

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
