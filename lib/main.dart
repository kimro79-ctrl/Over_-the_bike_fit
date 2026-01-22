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
  String _watchStatus = "Watch Search";

  // [수정] 워치 연결 버튼을 눌러야 권한 요청이 시작됨
  Future<void> _handleWatchConnect() async {
    print("워치 연결 시도 및 권한 요청 시작");
    
    // 블루투스 및 위치 권한 요청
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses[Permission.bluetoothScan]!.isGranted && 
        statuses[Permission.bluetoothConnect]!.isGranted) {
      setState(() => _watchStatus = "Searching...");
      // 여기에 블루투스 스캔 로직 시작
    } else {
      setState(() => _watchStatus = "Permission Denied");
    }
  }

  void _onActionButtonPressed(String msg) {
    print("[$msg] 버튼 터치 성공");
    // 실제 기능 연결 (시작/저장/기록 등)
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. 배경 (맨 아래) - 투명막 없음
          Positioned.fill(child: Image.asset('assets/background.png', fit: BoxFit.cover)),

          // 2. 하단 그라데이션 (디자인용, 터치 방해 안 함)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                ),
              ),
            ),
          ),

          // 3. 메인 UI (그래프 및 데이터)
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 20),
                
                // [워치 연결 버튼] 클릭 시에만 권한 요청
                GestureDetector(
                  onTap: _handleWatchConnect,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
                      color: Colors.black.withOpacity(0.3),
                    ),
                    child: Text(_watchStatus, style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                  ),
                ),

                const SizedBox(height: 30),

                // 가느다란 그래프
                SizedBox(
                  height: 60,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 50),
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(show: false),
                        titlesData: FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [const FlSpot(0, 1), const FlSpot(5, 4), const FlSpot(10, 2)],
                            isCurved: true,
                            barWidth: 0.8,
                            color: Colors.cyanAccent.withOpacity(0.8),
                            dotData: FlDotData(show: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // 데이터 배너
                Container(
                  width: MediaQuery.of(context).size.width * 0.9,
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white.withOpacity(0.1), Colors.transparent],
                    ),
                    border: Border.all(color: Colors.white10),
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

          // 4. 조작 버튼 (Stack 최상단 배치 + 위치 더 상향 조정)
          Positioned(
            bottom: 120, // 위치를 120으로 더 올려서 조작성 개선
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _pillButton(Icons.play_arrow, "START"),
                const SizedBox(width: 15),
                _pillButton(Icons.save, "SAVE"),
                const SizedBox(width: 15),
                _pillButton(Icons.bar_chart, "LOG"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillButton(IconData icon, String label) {
    return GestureDetector(
      onTap: () => _onActionButtonPressed(label),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 100, height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(
            colors: [Colors.white.withOpacity(0.15), Colors.white.withOpacity(0.05)],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _DataTile extends StatelessWidget {
  final String label, value;
  const _DataTile(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white60)),
        const SizedBox(height: 10),
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
