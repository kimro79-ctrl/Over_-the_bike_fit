import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:ui';

void main() => runApp(const BikeFitApp());

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark),
      home: const WorkoutScreen(),
    );
  }
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override
  _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0;
  int _avgHeartRate = 0;
  List<FlSpot> _hrSpots = [];
  int _timerCount = 0;
  String _watchStatus = "워치 검색";
  BluetoothDevice? _connectedDevice;
  StreamSubscription? _hrSubscription;

  // 1. 워치 검색 및 권한 설정
  Future<void> _handleWatchSearch() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    _startScanning();
  }

  void _startScanning() async {
    setState(() => _watchStatus = "검색 중...");
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        String name = r.device.platformName.toLowerCase();
        if (name.contains("amazfit") || name.contains("watch") || name.contains("gts")) {
          FlutterBluePlus.stopScan();
          _connectToDevice(r.device);
          break;
        }
      }
    });
  }

  // 2. 기기 연결 및 심박수 데이터 구독 (에러 수정 핵심)
  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() => _watchStatus = "연결 시도...");
    try {
      await device.connect();
      _connectedDevice = device;
      setState(() => _watchStatus = "연결됨: ${device.platformName}");

      List<BluetoothService> services = await device.discoverServices();
      for (var s in services) {
        if (s.uuid.toString().contains("180d")) { // 심박수 서비스
          for (var c in s.characteristics) {
            if (c.uuid.toString().contains("2a37")) { // 심박수 측정 특성
              
              // [최종 에러 해결] 최신 버전은 setNotifyValue를 사용합니다.
              await c.setNotifyValue(true); 
              
              _hrSubscription = c.lastValueStream.listen((value) {
                if (value.isNotEmpty && mounted) {
                  setState(() {
                    _heartRate = value[1]; 
                    if (_hrSpots.length > 50) _hrSpots.removeAt(0);
                    _hrSpots.add(FlSpot(_timerCount.toDouble(), _heartRate.toDouble()));
                    _timerCount++;
                    
                    double sum = _hrSpots.map((e) => e.y).reduce((a, b) => a + b);
                    _avgHeartRate = (sum / _hrSpots.length).round();
                  });
                }
              });
            }
          }
        }
      }
    } catch (e) {
      setState(() => _watchStatus = "연결 실패");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 배경 이미지
          Positioned.fill(child: Image.asset('assets/background.png', fit: BoxFit.cover)),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                
                const SizedBox(height: 15),
                // 워치 검색 버튼
                GestureDetector(
                  onTap: _handleWatchSearch,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
                    ),
                    child: Text(_watchStatus, style: const TextStyle(fontSize: 11, color: Colors.cyanAccent)),
                  ),
                ),

                const Spacer(),

                // 실시간 그래프
                SizedBox(
                  height: 130,
                  width: double.infinity,
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(show: false),
                      titlesData: FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots,
                          isCurved: true,
                          color: Colors.cyanAccent.withOpacity(0.8),
                          barWidth: 3,
                          dotData: FlDotData(show: false),
                          belowBarData: BarAreaData(show: true, color: Colors.cyanAccent.withOpacity(0.1)),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // 투명 데이터 배너
                _buildGlassPanel(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildDataTile("실시간", "$_heartRate", Colors.cyanAccent),
                      _buildDataTile("평균", "$_avgHeartRate", Colors.redAccent),
                      _buildDataTile("칼로리", "0.0", Colors.orangeAccent),
                      _buildDataTile("시간", "00:00", Colors.blueAccent),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // 하단 조작 버튼 (먹통 방지 로직 적용)
                Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildActionButton(Icons.play_arrow, "시작", () => print("시작")),
                      const SizedBox(width: 30),
                      _buildActionButton(Icons.save, "저장", () => print("저장")),
                      const SizedBox(width: 30),
                      _buildActionButton(Icons.bar_chart, "기록", () => print("기록")),
                    ],
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildDataTile(String l, String v, Color c) => Column(
    children: [
      Text(l, style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
    ],
  );

  Widget _buildGlassPanel({required Widget child}) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.9,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.01), // 초투명
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(padding: const EdgeInsets.all(25), child: child),
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData i, String l, VoidCallback t) => Column(
    children: [
      GestureDetector(
        onTap: t,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 65, height: 65,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Center(child: Icon(i, size: 28, color: Colors.white)),
        ),
      ),
      const SizedBox(height: 10),
      Text(l, style: const TextStyle(fontSize: 11, color: Colors.white30)),
    ],
  );
}
