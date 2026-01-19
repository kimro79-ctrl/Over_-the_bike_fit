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
  double calories = 0.0; // 칼로리 소모량 추가
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

  // 칼로리 계산 로직 (심박수 기반 간이 공식)
  void _updateCalories() {
    if (bpm > 0 && isRunning) {
      setState(() {
        // 남성 평균 기준 간이 식: (Age*0.2017 + Weight*0.1988 + HeartRate*0.6309 - 55.0969) * Time / 4.184
        // 여기서는 실시간 변화를 위해 아주 작은 단위로 매초 가산합니다.
        calories += (bpm * 0.002); 
      });
    }
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
                    if (heartRateSpots.length > 40) heartRateSpots.removeAt(0);
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
              const SizedBox(height: 15),
              const Text("OVER THE BIKE FIT", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 4, fontStyle: FontStyle.italic)),
              
              GestureDetector(
                onTap: _connectWatch,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(border: Border.all(color: connectedDevice != null ? neonColor : Colors.white24), borderRadius: BorderRadius.circular(20)),
                  child: Text(watchStatus, style: TextStyle(fontSize: 11, color: connectedDevice != null ? neonColor : Colors.white70)),
                ),
              ),

              const Spacer(flex: 2), // 배경 자전거 이미지를 더 많이 보여주기 위해 공간 확보

              // [수정] 전체의 1/3 정도로 슬림해진 데이터 카드
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 15),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75), 
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: neonColor.withOpacity(0.4), width: 1),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        // 심박수 영역
                        Column(
                          children: [
                            Text("HEART RATE", style: TextStyle(color: neonColor.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.bold)),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text("${bpm > 0 ? bpm : '--'}", style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: neonColor)),
                                const SizedBox(width: 4),
                                const Text("BPM", style: TextStyle(fontSize: 12, color: Colors.white70)),
                              ],
                            ),
                          ],
                        ),
                        // [신규] 칼로리 소모량 영역
                        Column(
                          children: [
                            Text("CALORIES", style: TextStyle(color: Colors.orangeAccent.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold)),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(calories.toStringAsFixed(1), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
                                const SizedBox(width: 4),
                                const Text("kcal", style: TextStyle(fontSize: 12, color: Colors.white70)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 슬림 그래프
                    SizedBox(
                      height: 80, // 높이를 대폭 줄여 배경 확보
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
                  ],
                ),
              ),

              const Spacer(flex: 1),

              // 운동 정보 (시간/목표)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildInfoColumn("운동시간", "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.redAccent),
                  Column(children: [
                    const Text("목표설정", style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Row(children: [
                      IconButton(onPressed: () => setState(() { if (targetMinutes > 1) targetMinutes--; }), icon: const Icon(Icons.remove, size: 18)),
                      Text("$targetMinutes분", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(onPressed: () => setState(() { targetMinutes++; }), icon: const Icon(Icons.add, size: 18)),
                    ]),
                  ]),
                ],
              ),

              // 하단 컨트롤 버튼
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 10, 15, 30),
                child: Row(children: [
                  _buildActionBtn(isRunning ? "정지" : "시작", isRunning ? Colors.grey : Colors.redAccent, () {
                    setState(() { 
                      isRunning = !isRunning; 
                      if (isRunning) {
                        workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
                          setState(() => elapsedSeconds++);
                          _updateCalories(); // 매초 칼로리 갱신
                        });
                      } else {
                        workoutTimer?.cancel();
                      }
                    });
                  }),
                  const SizedBox(width: 8),
                  _buildActionBtn("저장", Colors.green, () {
                    if (elapsedSeconds > 0) {
                      workoutLogs.add({"date": "${DateTime.now().month}/${DateTime.now().day}", "time": "${elapsedSeconds ~/ 60}분", "kcal": calories.toStringAsFixed(1)});
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 데이터 저장 완료")));
                    }
                  }),
                ]),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoColumn(String label, String value, Color color) {
    return Column(children: [Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)), Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color))]);
  }

  Widget _buildActionBtn(String text, Color color, VoidCallback onTap) {
    return Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: onTap, child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold))));
  }
}

// ... HistoryPage는 이전과 동일 (kcal 표시만 추가하면 됨)
class HistoryPage extends StatelessWidget {
  final List<Map<String, dynamic>> logs;
  const HistoryPage({super.key, required this.logs});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("기록 내역"), backgroundColor: Colors.black),
      body: ListView.builder(
        itemCount: logs.length,
        itemBuilder: (context, index) => ListTile(
          leading: const Icon(Icons.directions_bike, color: Color(0xFF00E5FF)),
          title: Text("${logs[index]['date']} 운동"),
          subtitle: Text("시간: ${logs[index]['time']} | 소모: ${logs[index]['kcal']} kcal"),
        ),
      ),
    );
  }
}
