import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';

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
  int targetMinutes = 20;
  int elapsedSeconds = 0;
  bool isRunning = false;
  String watchStatus = "탭하여 워치 연결";
  List<FlSpot> heartRateSpots = []; 
  static List<Map<String, dynamic>> workoutLogs = []; 
  
  BluetoothDevice? connectedDevice;
  StreamSubscription? hrSubscription;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () => FlutterNativeSplash.remove());
  }

  void _connectWatch() async {
    setState(() => watchStatus = "기기 검색 중...");
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        String name = r.device.platformName.toLowerCase();
        if (connectedDevice == null && (name.contains("amazfit") || r.advertisementData.serviceUuids.contains(Guid("180d")))) {
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
      setState(() { connectedDevice = device; watchStatus = "연결됨: ${device.platformName}"; });
      List<BluetoothService> services = await device.discoverServices();
      for (var s in services) {
        if (s.uuid == Guid("180d")) {
          for (var c in s.characteristics) {
            if (c.uuid == Guid("2a37")) {
              await c.setNotifyValue(true);
              hrSubscription = c.lastValueStream.listen((value) {
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
    } catch (e) { setState(() => watchStatus = "연결 실패: 재시도"); }
  }

  @override
  Widget build(BuildContext context) {
    const Color neonColor = Color(0xFF00E5FF); 

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/background.png"), fit: BoxFit.cover)),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 10),
              const Text("OVER THE BIKE FIT", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 4, fontStyle: FontStyle.italic)),
              
              GestureDetector(
                onTap: _connectWatch,
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 5),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(border: Border.all(color: connectedDevice != null ? neonColor : Colors.white24), borderRadius: BorderRadius.circular(20)),
                  child: Text(watchStatus, style: TextStyle(fontSize: 11, color: connectedDevice != null ? neonColor : Colors.white70)),
                ),
              ),

              // [수정] 슬림해진 가로형 배너 (심박수 숫자 + 그래프 합체)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 30, vertical: 5),
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6), 
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: neonColor.withOpacity(0.3), width: 1),
                ),
                child: Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("HEART RATE", style: TextStyle(color: neonColor.withOpacity(0.6), fontSize: 9, fontWeight: FontWeight.bold)),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text("${bpm > 0 ? bpm : '--'}", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: neonColor)),
                            const SizedBox(width: 4),
                            const Text("BPM", style: TextStyle(fontSize: 10, color: Colors.white70)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(width: 15),
                    // 슬림 그래프 영역
                    Expanded(
                      child: SizedBox(
                        height: 45, 
                        child: LineChart(LineChartData(
                          gridData: const FlGridData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [LineChartBarData(
                            spots: heartRateSpots.isEmpty ? [const FlSpot(0, 0)] : heartRateSpots,
                            isCurved: true,
                            color: neonColor,
                            barWidth: 2,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(show: true, color: neonColor.withOpacity(0.1))
                          )]
                        )),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(), // 이 공간이 넓어져서 자전거 배경이 잘 보입니다.

              Container(
                padding: const EdgeInsets.only(bottom: 30),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _infoBox("운동시간", "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.redAccent),
                        _targetBox(),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          _btn(isRunning ? "정지" : "시작", isRunning ? Colors.grey : Colors.redAccent, () {
                            setState(() { 
                              isRunning = !isRunning; 
                              if (isRunning) workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++));
                              else workoutTimer?.cancel();
                            });
                          }),
                          const SizedBox(width: 10),
                          _btn("저장", Colors.green, () {
                            if (elapsedSeconds > 0) {
                              workoutLogs.add({"date": "${DateTime.now().month}/${DateTime.now().day}", "time": "${elapsedSeconds ~/ 60}분", "maxBpm": "$bpm"});
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 기록 저장됨")));
                            }
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoBox(String label, String value, Color color) => Column(children: [Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)), Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color))]);
  
  Widget _targetBox() => Column(children: [
    const Text("목표설정", style: TextStyle(fontSize: 11, color: Colors.grey)),
    Row(children: [
      IconButton(onPressed: () => setState(() { if (targetMinutes > 1) targetMinutes--; }), icon: const Icon(Icons.remove_circle_outline, size: 20)),
      Text("$targetMinutes분", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      IconButton(onPressed: () => setState(() { targetMinutes++; }), icon: const Icon(Icons.add_circle_outline, size: 20)),
    ])
  ]);

  Widget _btn(String text, Color color, VoidCallback onTap) => Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: onTap, child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold))));
}

// 기록 페이지
class HistoryPage extends StatelessWidget {
  final List<Map<String, dynamic>> logs;
  const HistoryPage({super.key, required this.logs});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("기록 내역"), backgroundColor: Colors.black),
      body: logs.isEmpty 
        ? const Center(child: Text("기록이 없습니다."))
        : ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) => ListTile(
              leading: const Icon(Icons.directions_bike, color: Color(0xFF00E5FF)),
              title: Text("${logs[index]['date']} 운동"),
              subtitle: Text("시간: ${logs[index]['time']} | 최고 심박수: ${logs[index]['maxBpm']} BPM"),
            ),
          ),
    );
  }
}
