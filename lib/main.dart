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
    setState(() => watchStatus = "워치 찾는 중...");
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
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
                    if (heartRateSpots.length > 60) heartRateSpots.removeAt(0);
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
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/background.png"), fit: BoxFit.cover)),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Text("OVER THE BIKE FIT", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 3, fontStyle: FontStyle.italic)),
              
              GestureDetector(
                onTap: _connectWatch,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black45, border: Border.all(color: connectedDevice != null ? Colors.greenAccent : Colors.redAccent), borderRadius: BorderRadius.circular(20)),
                  child: Text(watchStatus, style: TextStyle(fontSize: 12, color: connectedDevice != null ? Colors.greenAccent : Colors.white)),
                ),
              ),

              const Spacer(flex: 1),
              
              if (bpm > 0) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text("$bpm", style: const TextStyle(fontSize: 65, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(width: 8),
                    const Text("BPM", style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 180,
                  width: MediaQuery.of(context).size.width * 0.9,
                  child: LineChart(LineChartData(
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [LineChartBarData(
                      spots: heartRateSpots,
                      isCurved: true,
                      color: Colors.redAccent,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: true, color: Colors.redAccent.withOpacity(0.15))
                    )]
                  )),
                ),
              ] else ...[
                const Icon(Icons.favorite, size: 60, color: Colors.white12),
                const SizedBox(height: 10),
                const Text("데이터 수신 대기 중...", style: TextStyle(color: Colors.white24, fontSize: 12)),
              ],

              const Spacer(flex: 2),

              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                color: Colors.black26,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(children: [const Text("운동시간", style: TextStyle(fontSize: 11, color: Colors.grey)), Text("${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.redAccent))]),
                    Column(
                      children: [
                        const Text("목표설정", style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Row(children: [
                          IconButton(onPressed: () => setState(() { if (targetMinutes > 1) targetMinutes--; }), icon: const Icon(Icons.remove, size: 20)),
                          Text("$targetMinutes분", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          IconButton(onPressed: () => setState(() { targetMinutes++; }), icon: const Icon(Icons.add, size: 20)),
                        ]),
                      ],
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(15, 10, 15, 30),
                child: Row(children: [
                  Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 15)), onPressed: () {
                    setState(() { isRunning = !isRunning; if (isRunning) workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++)); else workoutTimer?.cancel(); });
                  }, child: Text(isRunning ? "정지" : "시작", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
                  const SizedBox(width: 8),
                  Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 15)), onPressed: () {
                    if (elapsedSeconds > 0) {
                      workoutLogs.add({"date": "${DateTime.now().month}/${DateTime.now().day}", "time": "${elapsedSeconds ~/ 60}분", "maxBpm": "$bpm"});
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 기록 저장!")));
                    }
                  }, child: const Text("저장", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
                  const SizedBox(width: 8),
                  Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, padding: const EdgeInsets.symmetric(vertical: 15)), onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryPage(logs: workoutLogs)));
                  }, child: const Text("기록", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
                ]),
              )
            ],
          ),
        ),
      ),
    );
  }
}

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
              leading: const Icon(Icons.directions_bike, color: Colors.redAccent),
              title: Text("${logs[index]['date']} 운동"),
              subtitle: Text("시간: ${logs[index]['time']} | 최고 심박수: ${logs[index]['maxBpm']} BPM"),
            ),
          ),
    );
  }
}
