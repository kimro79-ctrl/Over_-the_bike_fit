import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const BikeFitApp());
  // 스플래시 화면 3초 유지
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
  String watchStatus = "탭하여 설정에서 워치 연결";
  Timer? workoutTimer;
  List<Map<String, dynamic>> workoutLogs = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  // 저장된 기록 불러오기
  Future<void> _loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('workout_history');
    if (data != null) setState(() => workoutLogs = List<Map<String, dynamic>>.from(json.decode(data)));
  }

  // 운동 기록 저장 함수
  Future<void> _saveLog() async {
    if (elapsedSeconds < 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("기록하기에 운동 시간이 너무 짧습니다.")));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final log = {
      "date": "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}",
      "duration": "${elapsedSeconds ~/ 60}분 ${elapsedSeconds % 60}초",
      "bpm": bpm > 0 ? "$bpm" : "--"
    };
    workoutLogs.insert(0, log);
    await prefs.setString('workout_history', json.encode(workoutLogs));
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 기록이 저장되었습니다!")));
  }

  // 워치 연결 버튼 클릭 시: 권한 체크 -> 설정 화면 이동
  Future<void> _handleWatchConnection() async {
    // 1. 권한 요청
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses.values.every((status) => status.isGranted)) {
      setState(() => watchStatus = "설정에서 연결 후 돌아오세요");
      
      // 2. 시스템 블루투스 설정 화면 열기
      // Note: FlutterBluePlus.turnOn()은 블루투스를 켜는 시도를 하며, 
      // 실제 설정 화면 이동은 사용자가 직접 시스템 바를 내리거나 설정 앱으로 가야 함을 안내
      await FlutterBluePlus.turnOn();
      
      // 3. 앱으로 돌아왔을 때 이미 연결된 기기가 있는지 확인 시도
      _checkConnectedDevices();
    } else {
      setState(() => watchStatus = "권한 허용이 필요합니다");
    }
  }

  void _checkConnectedDevices() async {
    List<BluetoothDevice> connectedDevices = FlutterBluePlus.connectedDevices;
    if (connectedDevices.isNotEmpty) {
      for (var device in connectedDevices) {
        if (device.platformName.toLowerCase().contains("watch") || device.platformName.toLowerCase().contains("fit")) {
          _establishBleStream(device);
          break;
        }
      }
    }
  }

  void _establishBleStream(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() => watchStatus = "연결됨: ${device.platformName}");
      List<BluetoothService> services = await device.discoverServices();
      for (var s in services) {
        if (s.uuid == Guid("180d")) { // 심박수 서비스
          for (var c in s.characteristics) {
            if (c.uuid == Guid("2a37")) { // 심박수 값
              await c.setNotifyValue(true);
              c.lastValueStream.listen((value) {
                if (value.isNotEmpty && mounted) setState(() => bpm = value[1]);
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint("연결 오류: $e");
    }
  }

  // 기록 리스트 팝업
  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Column(
        children: [
          const SizedBox(height: 20),
          const Text("운동 히스토리", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const Divider(color: Colors.white10),
          Expanded(
            child: workoutLogs.isEmpty 
              ? const Center(child: Text("저장된 기록이 없습니다."))
              : ListView.builder(
                  itemCount: workoutLogs.length,
                  itemBuilder: (context, i) => ListTile(
                    leading: const Icon(Icons.history_edu, color: Colors.cyanAccent),
                    title: Text(workoutLogs[i]['date'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("시간: ${workoutLogs[i]['duration']} | 심박수: ${workoutLogs[i]['bpm']}"),
                  ),
                ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const
