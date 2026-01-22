import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:ui'; // 유리 효과를 위한 추가

void main() => runApp(const BikeFitApp());

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark),
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
  int _avgHeartRate = 0; // 평균 심박 추가
  String _watchStatus = "권한 확인 중...";
  bool _isWorkingOut = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions(); // 앱 시작 시 권한부터 요청
  }

  // 1. 필수 권한 요청 로직 (워치 검색 안되는 문제 해결)
  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses[Permission.bluetoothScan]!.isGranted) {
      _startWatchScan();
    } else {
      setState(() => _watchStatus = "권한 필요");
    }
  }

  void _startWatchScan() async {
    setState(() => _watchStatus = "워치 검색 중...");
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName.contains("Watch") || r.device.platformName.contains("Galaxy")) {
          setState(() => _watchStatus = "연결됨: ${r.device.platformName}");
          // 실제 심박수 수신 로직은 여기에 추가 가능
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/background.png', fit: BoxFit.cover)),
          
          // 배경 그라데이션
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.2), Colors.black.withOpacity(0.9)],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 15),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                
                const SizedBox(height: 20),
                // 워치 검색창
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.watch, size: 14, color: Colors.cyanAccent),
                      const SizedBox(width: 8),
                      Text(_watchStatus, style: const TextStyle(fontSize: 11, color: Colors.white)),
                    ],
                  ),
                ),

                const Spacer(),

                // 2. 데이터 배너 (평균 심박 추가)
                _glassBox(
                  width: MediaQuery.of(context).size.width * 0.85,
                  padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _dataItem("심박수", "$_heartRate", Colors.cyanAccent),
                      _dataItem("평균심박", "$_avgHeartRate", Colors.redAccent), // 추가
                      _dataItem("칼로리", "0.0", Colors.orangeAccent),
                      _dataItem("시간", "00:00", Colors.blueAccent),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // 3. 버튼부 (둥근 사각형 + 유리 효과)
                Padding(
                  padding: const EdgeInsets.only(bottom: 50),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _glassBtn(Icons.play_arrow, "시작", () => setState(() => _isWorkingOut = !_isWorkingOut)),
                      const SizedBox(width: 20),
                      _glassBtn(Icons.save, "저장", () {}),
                      const SizedBox(width: 20),
                      _glassBtn(Icons.bar_chart, "기록", () {}),
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

  // 데이터 레이아웃
  Widget _dataItem(String l, String v, Color c) => Column(
    children: [
      Text(l, style: TextStyle(fontSize: 10, color: c.withOpacity(0.8))),
      const SizedBox(height: 5),
      Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
    ],
  );

  // 유리 효과 베이스 박스
  Widget _glassBox({required double width, required EdgeInsets padding, required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: width,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: child,
        ),
      ),
    );
  }

  // 유리 효과 버튼
  Widget _glassBtn(IconData i, String l, VoidCallback t) => Column(
    children: [
      GestureDetector(
        onTap: t,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              width: 65, height: 65,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Icon(i, size: 28, color: Colors.white.withOpacity(0.9)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(l, style: const TextStyle(fontSize: 11, color: Colors.white38)),
    ],
  );
}
