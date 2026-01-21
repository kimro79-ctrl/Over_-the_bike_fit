import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // 스플래시 화면 유지 시작
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  
  runApp(const BikeFitApp());

  // 3초간 스플래시 화면을 보여준 뒤 제거
  await Future.delayed(const Duration(seconds: 3));
  FlutterNativeSplash.remove();
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const WorkoutScreen(),
    );
  }
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});
  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int bpm = 0;
  int elapsedSeconds = 0;
  int targetMinutes = 20;
  bool isRunning = false;
  String watchStatus = "기기 자동 검색 중...";
  List<FlSpot> heartRateSpots = [];
  List<Map<String, dynamic>> workoutLogs = [];

  BluetoothDevice? connectedDevice;
  StreamSubscription? scanSubscription;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    // 앱 시작 시 자동으로 워치 연결 시도
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoConnect();
    });
  }

  Future<void> _loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('workout_history');
    if (data != null) setState(() => workoutLogs = List<Map<String, dynamic>>.from(json.decode(data)));
  }

  Future<void> _autoConnect() async {
    // 권한 확인 및 요청
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    
    _startAutoScan();
  }

  void _startAutoScan() async {
    setState(() => watchStatus = "워치 자동 연결 시도 중...");
    
    // 이미 연결된 기기가 있는지 확인
    List<BluetoothDevice> systemDevices = await FlutterBluePlus.systemDevices;
    for (var device in systemDevices) {
      if (device.platformName.toLowerCase().contains("watch") || device.platformName.toLowerCase().contains("amazfit")) {
        _establishConnection(device);
        return;
      }
    }

    // 주변 스캔 시작
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    scanSubscription?.cancel();
    scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        String name = r.device.platformName.toLowerCase();
        if (name.contains("watch") || name.contains("amazfit") || name.contains("galaxy")) {
          FlutterBluePlus.stopScan();
          _establishConnection(r.device);
          break;
        }
      }
    });
  }

  void _establishConnection(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      setState(() {
        connectedDevice = device;
        watchStatus = "연결 완료: ${device.platformName}";
      });

      List<BluetoothService> services = await device.discoverServices();
      for (var s in services) {
        if (s.uuid == Guid("180d")) { 
          for (var c in s.characteristics) {
            if (c.uuid == Guid("2a37")) { 
              await c.setNotifyValue(true);
              c.lastValueStream.listen((value) {
                if (value.isNotEmpty && mounted) {
                  setState(() {
                    bpm = value[1];
                    heartRateSpots.add(FlSpot(heartRateSpots.length.toDouble(), bpm.toDouble()));
                    if (heartRateSpots.length > 50) heartRateSpots.removeAt(0);
                  });
                }
              });
            }
          }
        }
      }
    } catch (e) {
      setState(() => watchStatus = "연결 실패 (탭하여 재시도)");
    }
  }

  // --- 기존 UI 컴포넌트 유지 ---
  Widget _infoBox(String label, String value, Color color) {
    return Column(children: [
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color))
    ]);
  }

  Widget _targetBox() {
    return Column(children: [
      const Text("목표설정", style: TextStyle(fontSize: 11, color: Colors.grey)),
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(onPressed: () => setState(() => targetMinutes--), icon: const Icon(Icons.remove_circle_outline)),
        Text("$targetMinutes분", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        IconButton(onPressed: () => setState(() => targetMinutes++), icon: const Icon(Icons.add_circle_outline)),
      ])
    ]);
  }

  Widget _btn(String text, Color color, VoidCallback onTap) {
    return Expanded(child: ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(vertical: 15)),
      onPressed: onTap, child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/background.png"), fit: BoxFit.cover)),
        child: SafeArea(
          child: Column(children: [
            const SizedBox(height: 30),
            const Text("OVER THE BIKE FIT", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic, letterSpacing: 2)),
            const SizedBox(height: 10),
            // 자동 연결 실패 시 수동으로 누를 수 있도록 GestureDetector 유지
            GestureDetector(onTap: _startAutoScan, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              decoration: BoxDecoration(border: Border.all(color: Colors.cyan), borderRadius: BorderRadius.circular(20)),
              child: Text(watchStatus, style: const TextStyle(color: Colors.cyan, fontSize: 13)),
            )),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(25),
              decoration: const BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _infoBox("운동시간", "${elapsedSeconds ~/ 60}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.redAccent),
                  _targetBox(),
                ]),
                const SizedBox(height: 25),
                Row(children: [
                  _btn(isRunning ? "정지" : "시작", isRunning ? Colors.grey : Colors.redAccent, () {
                    setState(() {
                      isRunning = !isRunning;
                      if (isRunning) workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++));
                      else workoutTimer?.cancel();
                    });
                  }),
                  const SizedBox(width: 15),
                  _btn("저장", Colors.green, () {
                    if (elapsedSeconds > 0) {
                      _saveLog({
                        "date": "${DateTime.now().month}/${DateTime.now().day}", 
                        "time": "${elapsedSeconds ~/ 60}분 ${elapsedSeconds % 60}초", 
                        "bpm": "$bpm"
                      });
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("기록이 저장되었습니다!")));
                    }
                  }),
                ]),
                const SizedBox(height: 15),
                const Text("본 앱은 의료기기가 아닙니다.", style: TextStyle(fontSize: 10, color: Colors.white24)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
