import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  // 데이터 변수
  int _heartRate = 0;
  int _avgHeartRate = 0;
  int _totalHRSum = 0;
  int _hrCount = 0;
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  
  // 상태 변수
  bool _isWorkingOut = false;     // 운동 중인지 여부
  bool _isWatchConnected = false; // 워치 연결 여부
  String _watchName = "Amazfit GTS2 mini"; // 발견된 워치 이름 예시

  // 타이머
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _vibrate() => HapticFeedback.lightImpact();

  // [핵심] 권한 요청 및 설정 화면 이동 로직
  Future<void> _handleWatchConnection() async {
    _vibrate();

    // 1. 필요한 권한 목록 정의 (Android 12 이상: 스캔/연결, 이하: 위치)
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    // 2. 권한 상태 확인
    bool isGranted = true;
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        isGranted = false;
      }
    });

    if (isGranted) {
      // 권한 허용됨 -> 연결 성공 시뮬레이션
      setState(() {
        _isWatchConnected = true;
        _heartRate = 70; // 초기 심박수
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("워치가 연결되었습니다!"), duration: Duration(seconds: 1)),
      );
    } else {
      // 3. 권한 거부됨 -> 설정 화면으로 이동 유도
      _showPermissionDialog();
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("권한 필요"),
        content: const Text("워치 연결을 위해 블루투스 및 위치 권한이 필요합니다.\n설정으로 이동하여 권한을 허용해주세요."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("취소"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings(); // [중요] 앱 설정 화면 열기
            },
            child: const Text("설정으로 이동"),
          ),
        ],
      ),
    );
  }

  // [핵심] 운동 시작/중지 및 타이머 로직
  void _toggleWorkout() {
    _vibrate();

    // 워치 연결 안 되어 있으면 경고
    if (!_isWatchConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("먼저 워치를 연결해주세요!"), duration: Duration(seconds: 1)),
      );
      return;
    }

    setState(() {
      _isWorkingOut = !_isWorkingOut; // 상태 토글

      if (_isWorkingOut) {
        // 운동 시작
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _duration += const Duration(seconds: 1); // 시간 증가
            
            // 데이터 시뮬레이션
            int currentHR = 110 + Random().nextInt(40); // 110~150 랜덤
            _heartRate = currentHR;
            _totalHRSum += currentHR;
            _hrCount++;
            _avgHeartRate = _totalHRSum ~/ _hrCount;
            _calories += 0.15; // 초당 칼로리
          });
        });
      } else {
        // 운동 중지
        _timer?.cancel();
      }
    });
  }

  // 초기화 및 저장
  void _saveWorkout() {
    _vibrate();
    if (_duration.inSeconds == 0) return;

    // 데이터 저장 로직 (여기선 초기화만 수행)
    setState(() {
      _isWorkingOut = false;
      _timer?.cancel();
      _duration = Duration.zero;
      _calories = 0.0;
      _heartRate = _isWatchConnected ? 70 : 0;
      _avgHeartRate = 0;
      _totalHRSum = 0;
      _hrCount = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("운동 기록이 저장되었습니다."), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 배경 이미지
          Positioned.fill(
            child: Opacity(
              opacity: 0.4, 
              child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (_,__,___)=>Container())
            )
          ),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 30),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.white)),
                const SizedBox(height: 20),
                
                // [워치 연결 버튼]
                GestureDetector(
                  onTap: _handleWatchConnection,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 50),
                    padding: const EdgeInsets.symmetric(vertical: 12), // 높이 살짝 키움
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30), // 더 둥글게
                      border: Border.all(color: _isWatchConnected ? Colors.cyanAccent : Colors.white30),
                      color: Colors.black.withOpacity(0.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isWatchConnected ? Icons.watch : Icons.bluetooth_searching, 
                          size: 18, 
                          color: _isWatchConnected ? Colors.cyanAccent : Colors.white70
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isWatchConnected ? "연결됨: $_watchName" : "워치 연결 (터치)",
                          style: TextStyle(
                            color: _isWatchConnected ? Colors.cyanAccent : Colors.white70, 
                            fontSize: 14,
                            fontWeight: _isWatchConnected ? FontWeight.bold : FontWeight.normal
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // [실시간 데이터 배너]
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    // 사진처럼 부드러운 그라데이션 느낌의 반투명 배경
                    color: const Color(0xFF222222).withOpacity(0.8),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, spreadRadius: 1)
                    ]
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _dataColumn("실시간", "$_heartRate", Colors.cyanAccent),
                      _dataColumn("평균", "$_avgHeartRate", Colors.redAccent),
                      _dataColumn("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
                      _dataColumn("시간", _formatDuration(_duration), Colors.blueAccent),
                    ],
                  ),
                ),
                
                const SizedBox(height: 50),

                // [하단 사각형 버튼 세트]
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 시작/중지 버튼 (상태에 따라 아이콘/글자 변경)
                      _squareBtn(
                        _isWorkingOut ? Icons.pause : Icons.play_arrow, 
                        _isWorkingOut ? "중지" : "시작", 
                        _toggleWorkout
                      ),
                      
                      // 저장 버튼
                      _squareBtn(Icons.save, "저장", _saveWorkout),
                      
                      // 기록 버튼 (기능 없음, UI만)
                      _squareBtn(Icons.list_alt, "기록", () {}),
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

  // 데이터 표시 위젯
  Widget _dataColumn(String label, String value, Color color) => Column(
    children: [
      Text(label, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
    ],
  );

  // 사각형 버튼 위젯
  Widget _squareBtn(IconData icon, String label, VoidCallback onTap) => Column(
    children: [
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 80, // 버튼 크기
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08), // 반투명 배경
            borderRadius: BorderRadius.circular(25), // 둥근 모서리
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: Icon(icon, size: 32, color: Colors.white), // 아이콘 크기 키움
        ),
      ),
      const SizedBox(height: 10),
      Text(label, style: const TextStyle(fontSize: 14, color: Colors.white70)),
    ],
  );

  String _formatDuration(Duration d) => 
    "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
