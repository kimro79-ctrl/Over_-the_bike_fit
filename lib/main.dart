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
  List<FlSpot> heartRateSpots = []; // 그래프용 데이터 리스트
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
        if (connectedDevice == null && (r.device.platformName.isNotEmpty || r.advertisementData.serviceUuids.contains(Guid("180d")))) {
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
      for (var s in services) {
        if (s.uuid == Guid("180d")) {
          for (var c in s.characteristics) {
            if (c.uuid == Guid("2a37")) {
              await c.setNotifyValue(true);
              hrSubscription = c.lastValueStream.listen((value) {
                if (value.isNotEmpty && mounted) {
                  setState(() {
                    bpm = value[1];
                    if (isRunning) {
                      heartRateSpots.add(FlSpot(elapsedSeconds.toDouble(), bpm.toDouble()));
                      if (heartRateSpots.length > 50) heartRateSpots.removeAt(0);
                    }
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
              const SizedBox(height: 30),
              const Text("OVER THE BIKE FIT", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 4, fontStyle: FontStyle.italic)),
              
              GestureDetector(
                onTap: _connectWatch,
                child: Container(
                  margin: const EdgeInsets.only(top: 15),
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), border: Border.all(color: connectedDevice != null ? Colors.greenAccent : Colors.redAccent.withOpacity(0.5)), borderRadius: BorderRadius.circular(20)),
                  child: Text(watchStatus, style: TextStyle(fontSize: 12, color: connectedDevice != null ? Colors.greenAccent : Colors.white)),
                ),
              ),

              const Spacer(),
              // 실시간 심박수 및 그래프 영역
              if (bpm > 0) ...[
                Text("$bpm", style: const TextStyle(fontSize: 90, fontWeight: FontWeight.bold)),
                const Text("BPM", style: TextStyle(color: Colors.redAccent, letterSpacing: 5)),
                const SizedBox(height: 20),
                SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: LineChart(LineChartData(
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [LineChartBarData(spots: heartRateSpots, isCurved: true, color: Colors.redAccent, barWidth: 3, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: Colors.redAccent.withOpacity(0.1)))]
                  )),
                ),
              ] else ...[
                const Icon(Icons.favorite_outline, size: 80, color: Colors.white10),
              ],
              const Spacer(),

              // 운동 정보 & 시간 조절 (버튼 부활)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(children: [const Text("운동시간", style: TextStyle(fontSize: 12, color: Colors.grey)), Text("${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.redAccent))]),
                  Column(
                    children: [
                      const Text("목표시간", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Row(children: [
                        IconButton(onPressed: () => setState(() { if (targetMinutes > 1) targetMinutes--; }), icon: const Icon(Icons.remove_circle_outline, color: Colors.white54)),
                        Text("$targetMinutes분", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        IconButton(onPressed: () => setState(() { targetMinutes++; }), icon: const Icon(Icons.add_circle_outline, color: Colors.white54)),
                      ]),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 30),

              // 하단 버튼 1:1:1
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 50),
                child: Row(children: [
                  Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 18)), onPressed: () {
                    setState(() { isRunning = !isRunning; if (isRunning) workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++)); else workoutTimer?.cancel(); });
                  }, child: Text(isRunning ? "정지" : "시작", style: const TextStyle(fontWeight: FontWeight.bold)))),
                  const SizedBox(width: 10),
                  Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green.withOpacity(0.8), padding: const EdgeInsets.symmetric(vertical: 18)), onPressed: () {
                    if (elapsedSeconds > 0) {
                      workoutLogs.add({"date": "${DateTime.now().month}/${DateTime.now().day}", "time": "${elapsedSeconds ~/ 60}분", "maxBpm": "$bpm"});
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 기록이 성공적으로 저장되었습니다.")));
                      setState(() { isRunning = false; workoutTimer?.cancel(); elapsedSeconds = 0; heartRateSpots.clear(); });
                    }
                  }, child: const Text("저장", style: TextStyle(fontWeight: FontWeight.bold)))),
                  const SizedBox(width: 10),
                  Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, padding: const EdgeInsets.symmetric(vertical: 18)), onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryPage(logs: workoutLogs)));
                  }, child: const Text("기록", style: TextStyle(fontWeight: FontWeight.bold)))),
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
      appBar: AppBar(title: const Text("나의 운동 기록"), backgroundColor: Colors.black),
      body: logs.isEmpty 
        ? const Center(child: Text("아직 저장된 운동 기록이 없습니다."))
        : ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) => ListTile(
              leading: const Icon(Icons.pedal_bike, color: Colors.redAccent),
              title: Text("${logs[index]['date']} 라이딩"),
              subtitle: Text("시간: ${logs[index]['time']} | 최고 심박수: ${logs[index]['maxBpm']} BPM"),
              trailing: const Icon(Icons.chevron_right, color: Colors.white24),
            ),
          ),
    );
  }
}
