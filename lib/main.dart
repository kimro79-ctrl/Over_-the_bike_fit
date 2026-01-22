import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const BikeFitApp());
  await Future.delayed(const Duration(milliseconds: 2500));
  FlutterNativeSplash.remove();
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.dark(primary: const Color(0xFF00E5FF)),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
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
  double totalCalories = 0.0;
  List<FlSpot> heartRateSpots = [];
  Timer? workoutTimer;
  BluetoothDevice? heartRateMonitor;
  BluetoothCharacteristic? heartRateChar;
  StreamSubscription<List<int>>? hrSubscription;
  StreamSubscription? scanSubscription;

  @override
  void initState() {
    super.initState();
    _requestBluetoothPermissions();
  }

  Future<void> _requestBluetoothPermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    if (statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied)) {
      // 필요 시 설정 화면으로 유도
      openAppSettings();
    }
  }

  Future<void> _connectToHeartRateMonitor() async {
    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid('180d')], // Heart Rate Service UUID
        timeout: const Duration(seconds: 5),
      );

      scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
          if (r.advertisementData.serviceUuids.contains(Guid('180d'))) {
            heartRateMonitor = r.device;
            await FlutterBluePlus.stopScan();
            scanSubscription?.cancel();

            await heartRateMonitor!.connect(timeout: const Duration(seconds: 10));
            final services = await heartRateMonitor!.discoverServices();

            for (var service in services) {
              if (service.uuid == Guid('180d')) {
                heartRateChar = service.characteristics.firstWhere(
                  (c) => c.uuid == Guid('2a37'),
                  orElse: () => throw Exception('Heart Rate Measurement not found'),
                );

                await heartRateChar!.setNotifyValue(true);
                hrSubscription = heartRateChar!.lastValueStream.listen((value) {
                  if (value.length > 1) {
                    final flags = value[0];
                    final rate16 = (flags & 0x01) != 0;
                    final bpmValue = rate16
                        ? (value[2] << 8) | value[1]
                        : value[1];

                    if (bpmValue > 0 && bpmValue < 250) {
                      setState(() {
                        bpm = bpmValue;
                        heartRateSpots.add(FlSpot(elapsedSeconds.toDouble(), bpmValue.toDouble()));
                        if (heartRateSpots.length > 120) {
                          heartRateSpots.removeAt(0); // 최근 2분 데이터 유지
                        }
                      });
                    }
                  }
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('심박수 모니터 연결 성공')),
                );
                return;
              }
            }
          }
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('연결 실패: $e')),
      );
    }
  }

  void _startTimer() {
    isRunning = true;
    workoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        elapsedSeconds++;
        // 칼로리: MET 8.0 (실내 사이클링 중강도), 체중 70kg 가정 → 1초당 kcal
        totalCalories += (8.0 * 70 / 3600); // 정확한 초당 증가

        if (elapsedSeconds >= targetMinutes * 60) {
          timer.cancel();
          isRunning = false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('목표 시간 달성! 훌륭합니다.')),
          );
        }
      });
    });
    _connectToHeartRateMonitor(); // 시작과 동시에 연결 시도
  }

  void _stopTimer() {
    workoutTimer?.cancel();
    hrSubscription?.cancel();
    scanSubscription?.cancel();
    heartRateMonitor?.disconnect();
    setState(() {
      isRunning = false;
      bpm = 0;
    });
  }

  Future<void> _saveRecord() async {
    final prefs = await SharedPreferences.getInstance();
    final record = {
      'timestamp': DateTime.now().toIso8601String(),
      'duration_sec': elapsedSeconds,
      'calories': totalCalories.toStringAsFixed(1),
      'avg_bpm': heartRateSpots.isEmpty
          ? 0
          : (heartRateSpots.map((s) => s.y).reduce((a, b) => a + b) / heartRateSpots.length).toStringAsFixed(0),
    };

    List<String> history = prefs.getStringList('bike_fit_history') ?? [];
    history.add(jsonEncode(record));
    await prefs.setStringList('bike_fit_history', history);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('이번 운동 기록이 저장되었습니다')),
    );
  }

  Widget _buildInfoItem(String label, String value, Color color) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white60)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _buildTargetControl() {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("목표 시간", style: TextStyle(fontSize: 11, color: Colors.white60)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => setState(() => targetMinutes = math.max(5, targetMinutes - 5)),
                child: const Icon(Icons.remove_circle_outline, size: 24, color: Colors.white70),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  "$targetMinutes 분",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => targetMinutes += 5),
                child: const Icon(Icons.add_circle_outline, size: 24, color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const neonCyan = Color(0xFF00E5FF);
    final timeDisplay = "\( {(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}: \){(elapsedSeconds % 60).toString().padLeft(2, '0')}";

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/background.png"),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Colors.black54, BlendMode.darken),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Text(
                  "OVER THE BIKE FIT",
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 실시간 심박수 그래프
              SizedBox(
                height: 220,
                child: heartRateSpots.isEmpty
                    ? const Center(child: Text("심박수 데이터 대기 중...", style: TextStyle(color: Colors.white54)))
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: LineChart(
                          LineChartData(
                            gridData: const FlGridData(show: false),
                            titlesData: const FlTitlesData(show: false),
                            borderData: FlBorderData(show: false),
                            minX: math.max(0, elapsedSeconds - 120).toDouble(),
                            maxX: elapsedSeconds.toDouble(),
                            minY: 40,
                            maxY: 200,
                            lineBarsData: [
                              LineChartBarData(
                                spots: heartRateSpots,
                                isCurved: true,
                                curveSmoothness: 0.4,
                                color: neonCyan,
                                barWidth: 4,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: neonCyan.withOpacity(0.15),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),

              const Spacer(),

              // 하단 정보 & 컨트롤 패널
              Container(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.92)],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildInfoItem("BPM", bpm > 0 ? bpm.toString() : "-", neonCyan),
                        _buildInfoItem("칼로리", "${totalCalories.toStringAsFixed(1)} kcal", neonCyan),
                        _buildInfoItem("시간", timeDisplay, Colors.white),
                        _buildTargetControl(),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(isRunning ? Icons.pause : Icons.play_arrow, color: Colors.white),
                            label: Text(isRunning ? "정지" : "시작", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isRunning ? Colors.grey[800] : Colors.redAccent,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                            ),
                            onPressed: () {
                              if (isRunning) {
                                _stopTimer();
                              } else {
                                _startTimer();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.save, color: Colors.white),
                            label: const Text("저장", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueGrey[700],
                              padding: const EdgeInsets.symmetric(vertical: 18),
                            ),
                            onPressed: elapsedSeconds > 60 ? _saveRecord : null, // 1분 이상 운동 시만 활성화
                          ),
                        ),
                      ],
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

  @override
  void dispose() {
    workoutTimer?.cancel();
    hrSubscription?.cancel();
    scanSubscription?.cancel();
    heartRateMonitor?.disconnect();
    super.dispose();
  }
}
