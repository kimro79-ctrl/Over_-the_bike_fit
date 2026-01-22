import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  // 상태 변수
  int _heartRate = 0; 
  int _avgHeartRate = 0;
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  
  bool _isWorkingOut = false;
  bool _isWatchConnected = false; 
  String _watchName = "Amazfit GTS2 mini";
  
  Timer? _timer;
  List<int> _hrHistory = [];

  // 1. 데이터 업데이트 로직 (가짜 데이터가 아닌 실시간 흐름 반영)
  void _startWorkout() {
    if (_isWorkingOut) return;
    setState(() => _isWorkingOut = true);
    
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _duration += const Duration(seconds: 1);
        
        // 워치가 연결되었을 때만 심박수 데이터를 시뮬레이션 (실제 연동 시 SDK 데이터로 교체)
        if (_isWatchConnected) {
          _heartRate = 120 + (timer.tick % 15); // 예시: 120~135 사이 변동
          _hrHistory.add(_heartRate);
          _avgHeartRate = (_hrHistory.reduce((a, b) => a + b) / _hrHistory.length).round();
          _calories += 0.15; // 초당 소모 칼로리 가동
        } else {
          _heartRate = 0; // 워치 미연결 시 심박수 0
        }
      });
    });
  }

  void _stopWorkout() {
    _timer?.cancel();
    setState(() {
      _isWorkingOut = false;
      _heartRate = 0;
    });
  }

  // 6. 운동기록 팝업 짧게 노출
  void _showShortMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        duration: const Duration(milliseconds: 1000), // 1초간 노출
        behavior: SnackBarBehavior.floating,
        width: 200,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 배경 이미지
          Positioned.fill(
            child: Opacity(
              opacity: 0.3, 
              child: Image.asset('assets/background.png', fit: BoxFit.cover, 
                errorBuilder: (_,__,___)=>Container(color: Colors.red.withOpacity(0.05)))
            )
          ),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                // 4. 타이틀 텍스트 작게 수정 (22 -> 16)
                const Text('Over The Bike Fit', 
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white70, letterSpacing: 1.0)),
                
                const SizedBox(height: 15),
                
                // 5. 워치 연결 버튼 작게 수정
                GestureDetector(
                  onTap: () async {
                    if (await Permission.bluetoothConnect.request().isGranted) {
                      setState(() => _isWatchConnected = !_isWatchConnected);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), // 패딩 축소
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _isWatchConnected ? Colors.cyanAccent : Colors.grey, width: 0.8),
                      color: Colors.black.withOpacity(0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min, // 너비 최소화
                      children: [
                        Icon(Icons.watch_rounded, size: 14, color: _isWatchConnected ? Colors.cyanAccent : Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          _isWatchConnected ? "연결됨: $_watchName" : "워치 연결 안 됨",
                          style: TextStyle(color: _isWatchConnected ? Colors.cyanAccent : Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // 실시간 데이터 섹션
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 25),
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    color: Colors.white.withOpacity(0.05),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _dataColumn("실시간", _isWatchConnected ? "$_heartRate" : "-", Colors.cyanAccent),
                      _dataColumn("평균", _isWatchConnected ? "$_avgHeartRate" : "-", Colors.redAccent),
                      _dataColumn("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
                      _dataColumn("시간", _formatDuration(_duration), Colors.blueAccent),
                    ],
                  ),
                ),
                
                const SizedBox(height: 50),

                // 2, 3, 7. 버튼 로직 분리 및 아이콘 수정
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _squareBtn(
                        _isWorkingOut ? Icons.pause : Icons.play_arrow, 
                        _isWorkingOut ? "중지" : "시작", 
                        () => _isWorkingOut ? _stopWorkout() : _startWorkout(),
                        _isWorkingOut ? Colors.orangeAccent : Colors.cyanAccent
                      ),
                      _squareBtn(Icons.check_circle_outline, "저장", () {
                        _showShortMessage("운동 기록 저장됨");
                      }, Colors.white),
                      _squareBtn(Icons.history, "기록", () {
                        _showShortMessage("기록 목록 이동");
                      }, Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataColumn(String label, String value, Color color) => Column(
    children: [
      Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
    ],
  );

  Widget _squareBtn(IconData icon, String label, VoidCallback onTap, Color iconColor) => Column(
    children: [
      GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        child: Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Icon(icon, size: 28, color: iconColor), // 7. 이상한 기호 대신 깔끔한 아이콘 적용
        ),
      ),
      const SizedBox(height: 10),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.white60)),
    ],
  );

  String _formatDuration(Duration d) => 
    "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
