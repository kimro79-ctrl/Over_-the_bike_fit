import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'dart:math';

void main() {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const BikeFitApp());
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
  int targetMinutes = 20; // 목표 시간 기본값
  int elapsedSeconds = 0;
  bool isRunning = false;
  String watchStatus = "탭하여 워치 연결";
  List<double> heartPoints = List.generate(45, (index) => 10.0);
  List<String> workoutHistory = [];
  
  BluetoothDevice? connectedDevice;
  StreamSubscription? hrSubscription;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () => FlutterNativeSplash.remove());
  }

  // 워치 연결 로직 (기존 유지)
  void _connectWatch() async {
    setState(() => watchStatus = "워치 찾는 중...");
    await FlutterBluePlus.startScan(withServices: [Guid("180d")], timeout: const Duration(seconds: 5));
    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        if (connectedDevice == null) {
          await FlutterBluePlus.stopScan();
          _establishConnection(r.device);
          break;
        }
      }
    });
  }

  void _establishConnection(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() { connectedDevice = device; watchStatus = "${device.platformName} 연결됨"; });
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid == Guid("180d")) {
          for (var char in service.characteristics) {
            if (char.uuid == Guid("2a37")) {
              await char.setNotifyValue(true);
              hrSubscription = char.lastValueStream.listen((value) {
                if (value.isNotEmpty && mounted) {
                  setState(() {
                    bpm = value[1];
                    heartPoints.add(bpm.toDouble() / 5);
                    heartPoints.removeAt(0);
                  });
                }
              });
            }
          }
        }
      }
    } catch (e) { setState(() => watchStatus = "연결 실패: 재시도"); }
  }

  void _toggleWorkout() {
    setState(() {
      isRunning = !isRunning;
      if (isRunning) {
        workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++));
      } else { workoutTimer?.cancel(); }
    });
  }

  @override
  void dispose() {
    hrSubscription?.cancel();
    workoutTimer?.cancel();
    super.dispose();
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
              // 세련된 타이틀
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(colors: [Colors.white, Colors.redAccent]).createShader(bounds),
                child: const Text("OVER THE BIKE FIT", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 6, fontStyle: FontStyle.italic)),
              ),
              
              // 워치 연결 상태
              GestureDetector(
                onTap: _connectWatch,
                child: Container(
                  margin: const EdgeInsets.only(top: 15),
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    border: Border.all(color: connectedDevice != null ? Colors.greenAccent : Colors.redAccent.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.watch, size: 14, color: connectedDevice != null ? Colors.greenAccent : Colors.grey),
                    const SizedBox(width: 8),
                    Text(watchStatus, style: TextStyle(fontSize: 11, color: connectedDevice != null ? Colors.greenAccent : Colors.white)),
                  ]),
                ),
              ),

              const Spacer(),
              
              // 중앙 디스플레이: 워치 연결 시 심박수, 아니면 기본 정보
              if (bpm > 0) ...[
                Text("$bpm", style: const TextStyle(fontSize: 90, fontWeight: FontWeight.bold)),
                const Text("BPM", style: TextStyle(color: Colors.redAccent, letterSpacing: 5)),
              ] else ...[
                const Icon(Icons.pedal_bike, size: 80, color: Colors.white24),
                const SizedBox(height: 10),
                const Text("READY TO RIDE", style: TextStyle(color: Colors.grey, letterSpacing: 3)),
              ],

              const Spacer(),

              // 정보 섹션 및 시간 조정 버튼
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // 운동시간 표시
                    statUnit("운동시간", "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.redAccent),
                    
                    // [부활] 목표시간 조정 섹션
                    Column(
                      children: [
                        const Text("목표시간", style: TextStyle(color: Colors.grey, fontSize: 10)),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => setState(() { if (targetMinutes > 1) targetMinutes--; }),
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.white54, size: 20),
                            ),
                            Text("$targetMinutes분", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                            IconButton(
                              onPressed: () => setState(() { targetMinutes++; }),
                              icon: const Icon(Icons.add_circle_outline, color: Colors.white54, size: 20),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // 하단 버튼 3등분 밸런스
              Container(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 50),
                child: Row(
                  children: [
                    actionBtn(isRunning ? "정지" : "시작", isRunning ? Colors.orange : Colors.redAccent, _toggleWorkout),
                    const SizedBox(width: 10),
                    actionBtn("저장", Colors.green.withOpacity(0.7), () {
                      if (elapsedSeconds > 0) {
                        workoutHistory.add("${DateTime.now().hour}:${DateTime.now().minute} - ${elapsedSeconds ~/ 60}분 운동");
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("기록 완료")));
                      }
                    }),
                    const SizedBox(width: 10),
                    actionBtn("기록", Colors.blueGrey, () {
                      // 기록 보기 로직 추가 가능
                    }),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget statUnit(String label, String val, Color col) => Column(children: [Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)), const SizedBox(height: 10), Text(val, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: col))]);

  Widget actionBtn(String label, Color col, VoidCallback fn) => Expanded(
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: col, 
        padding: const EdgeInsets.symmetric(vertical: 18), 
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
      ),
      onPressed: fn, 
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))
    )
  );
}
