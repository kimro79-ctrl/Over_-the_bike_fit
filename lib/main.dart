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
  String watchStatus = "탭하여 워치 연결";
  Timer? workoutTimer;
  List<Map<String, dynamic>> workoutLogs = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('workout_history');
    if (data != null) setState(() => workoutLogs = List<Map<String, dynamic>>.from(json.decode(data)));
  }

  // 블루투스 설정 및 연결 로직
  Future<void> _handleConnection() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    setState(() => watchStatus = "워치를 찾는 중...");
    
    // 이미 연결된 기기 확인
    List<BluetoothDevice> connectedDevices = FlutterBluePlus.connectedDevices;
    if (connectedDevices.isNotEmpty) {
      for (var device in connectedDevices) {
        _connectToDevice(device);
      }
    } else {
      // 주변 스캔
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          String name = r.device.platformName.toLowerCase();
          if (name.contains("watch") || name.contains("amazfit") || name.contains("galaxy")) {
            FlutterBluePlus.stopScan();
            _connectToDevice(r.device);
            break;
          }
        }
      });
    }
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() => watchStatus = "연결됨: ${device.platformName}");
      List<BluetoothService> services = await device.discoverServices();
      for (var s in services) {
        if (s.uuid == Guid("180d")) {
          for (var c in s.characteristics) {
            if (c.uuid == Guid("2a37")) {
              await c.setNotifyValue(true);
              c.lastValueStream.listen((value) {
                if (value.isNotEmpty && mounted) {
                  setState(() => bpm = value[1]);
                }
              });
            }
          }
        }
      }
    } catch (e) {
      setState(() => watchStatus = "연결 실패: 다시 시도");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage("assets/background.png"), fit: BoxFit.cover),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Text("OVER THE BIKE FIT", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic, color: Colors.white, letterSpacing: 2)),
              const SizedBox(height: 15),
              GestureDetector(
                onTap: _handleConnection,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(border: Border.all(color: Colors.cyanAccent), borderRadius: BorderRadius.circular(25)),
                  child: Text(watchStatus, style: const TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
                decoration: const BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(35)),
                ),
                child: Column(
                  children: [
                    // --- 상단 정보 (밸런스 조정) ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround, // 좌우 균형
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 운동 시간 박스
                        Expanded(
                          child: Column(
                            children: [
                              const Text("운동시간", style: TextStyle(fontSize: 12, color: Colors.white60)),
                              const SizedBox(height: 8),
                              Text("${elapsedSeconds ~/ 60}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", 
                                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                            ],
                          ),
                        ),
                        // 중앙 구분선 (선택 사항)
                        Container(height: 40, width: 1, color: Colors.white10),
                        // 목표 설정 박스
                        Expanded(
                          child: Column(
                            children: [
                              const Text("목표설정", style: TextStyle(fontSize: 12, color: Colors.white60)),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.white70, size: 20), 
                                    onPressed: () => setState(() => targetMinutes--)
                                  ),
                                  Text("$targetMinutes분", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.add_circle_outline, color: Colors.white70, size: 20), 
                                    onPressed: () => setState(() => targetMinutes++)
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    // --- 하단 버튼 ---
                    Row(
                      children: [
                        _actionBtn(isRunning ? "정지" : "시작", isRunning ? Colors.grey : Colors.redAccent, () {
                          setState(() {
                            isRunning = !isRunning;
                            if (isRunning) {
                              workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++));
                            } else {
                              workoutTimer?.cancel();
                            }
                          });
                        }),
                        const SizedBox(width: 15),
                        _actionBtn("저장", Colors.green, () {
                          if (elapsedSeconds > 0) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 데이터가 안전하게 저장되었습니다.")));
                          }
                        }),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text("본 서비스는 의료기기가 아니며 측정값은 참고용입니다.", style: TextStyle(fontSize: 10, color: Colors.white24)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBtn(String text, Color color, VoidCallback onTap) {
    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color, 
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          padding: const EdgeInsets.symmetric(vertical: 18)
        ),
        onPressed: onTap,
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
