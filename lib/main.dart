import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';

void main() => runApp(const BikeFitApp());

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: Colors.black),
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
  String _watchStatus = "워치 연결";
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  // 워치 연결 및 권한 요청 로직
  Future<void> _handleWatchConnect() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses[Permission.bluetoothScan]!.isGranted && 
        statuses[Permission.bluetoothConnect]!.isGranted) {
      setState(() => _watchStatus = "검색 중...");
      try {
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
        _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
          for (ScanResult r in results) {
            print('기기 발견: ${r.device.platformName}');
          }
        });
      } catch (e) {
        setState(() => _watchStatus = "오류 발생");
      }
    } else {
      setState(() => _watchStatus = "권한 필요");
    }
  }

  void _onAction(String label) {
    print("[$label] 클릭됨");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. 배경 이미지
          Positioned.fill(child: Image.asset('assets/background.png', fit: BoxFit.cover)),

          // 2. 어두운 오버레이 (배경을 차분하게 눌러줌)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                ),
              ),
            ),
          ),

          // 3. 메인 레이아웃
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),
                const Text('Over The Bike Fit', 
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                const SizedBox(height: 15),
                
                // [수정] 크기를 줄인 워치 연결 버튼
                GestureDetector(
                  onTap: _handleWatchConnect,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.4), width: 0.5),
                      color: Colors.black.withOpacity(0.5),
                    ),
                    child: Text(_watchStatus, 
                      style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),

                const SizedBox(height: 50),

                // [수정] 아주 가느다란 그래프 (barWidth: 0.5)
                SizedBox(
                  height: 40,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 70),
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(show: false),
                        titlesData: FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [const FlSpot(0, 1), const FlSpot(2, 3), const FlSpot(4, 2), const FlSpot(6, 4), const FlSpot(8, 2), const FlSpot(10, 3)],
                            isCurved: true,
                            barWidth: 0.5, // 초미세 선
                            color: Colors.cyanAccent.withOpacity(0.6),
                            dotData: FlDotData(show: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // [수정] 더 어두워진 데이터 배너
                Container(
                  width: MediaQuery.of(context).size.width * 0.9,
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    color: Colors.black.withOpacity(0.85), // 매우 어둡게 변경
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _DataTile("실시간", "0"),
                      _DataTile("평균", "0"),
                      _DataTile("칼로리", "0.0"),
                      _DataTile("시간", "00:00"),
                    ],
                  ),
                ),
                const SizedBox(height: 180), 
              ],
            ),
          ),

          // 4. 하단 버튼 (위치 유지 및 한글)
          Positioned(
            bottom: 120, 
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _pillButton(Icons.play_arrow, "시작", () => _onAction("시작")),
                const SizedBox(width: 15),
                _pillButton(Icons.save, "저장", () => _onAction("저장")),
                const SizedBox(width: 15),
                _pillButton(Icons.bar_chart, "기록", () => _onAction("기록")),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 95, height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.02)],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }
}

class _DataTile extends StatelessWidget {
  final String label, value;
  const _DataTile(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white38)),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
      ],
    );
  }
}
