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
    // 3초 후 스플래시 제거
    Future.delayed(const Duration(seconds: 3), () => FlutterNativeSplash.remove());
  }

  // 블루투스 워치 연결 로직
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
      setState(() {
        connectedDevice = device;
        watchStatus = "${device.platformName} 연결됨";
      });

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
    } catch (e) {
      setState(() => watchStatus = "연결 실패: 재시도");
    }
  }

  void _toggleWorkout() {
    setState(() {
      isRunning = !isRunning;
      if (isRunning) {
        workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++));
      } else {
        workoutTimer?.cancel();
      }
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
              // 세련된 그라데이션 타이틀
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(colors: [Colors.white, Colors.redAccent]).createShader(bounds),
                child: const Text("OVER THE BIKE FIT", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 6, fontStyle: FontStyle.italic)),
              ),
              
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
              // 심박수 중앙 집중 UI
              if (bpm > 0) ...[
                Text("$bpm", style: const TextStyle(fontSize: 90, fontWeight: FontWeight.bold)),
                const Text("BPM", style: TextStyle(color: Colors.redAccent, letterSpacing: 5)),
                const SizedBox(height: 20),
                SizedBox(height: 40, width: 220, child: CustomPaint(painter: MiniNeonPainter(heartPoints))),
              ],
              const Spacer(),

              // 하단 버튼 3등분 밸런스
              Container(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 50),
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
                    actionBtn("기록", Colors.blueGrey, () {}),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget actionBtn(String label, Color col, VoidCallback fn) => Expanded(
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: col, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      onPressed: fn, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))
    )
  );
}

class MiniNeonPainter extends CustomPainter {
  final List<double> points;
  MiniNeonPainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.redAccent..strokeWidth = 2.0..style = PaintingStyle.stroke;
    final path = Path();
    final xStep = size.width / (points.length - 1);
    path.moveTo(0, size.height / 2);
    for (int i = 0; i < points.length; i++) {
      path.lineTo(i * xStep, size.height - (points[i] % size.height));
    }
    canvas.drawPath(path, paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
