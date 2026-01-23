import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BikeFitApp());
}

// 1. 운동 기록 저장용 데이터 모델
class WorkoutRecord {
  final String date;
  final int avgHR;
  final double calories;
  final Duration duration;
  WorkoutRecord(this.date, this.avgHR, this.calories, this.duration);
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
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
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;

  bool _isWorkingOut = false;
  bool _isWatchConnected = false;
  List<FlSpot> _hrSpots = []; 
  double _timeCounter = 0;
  List<WorkoutRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final String? recordsJson = prefs.getString('workout_records');
    if (recordsJson != null) {
      final List<dynamic> decodedList = jsonDecode(recordsJson);
      setState(() {
        _records = decodedList.map((item) => WorkoutRecord(
          item['date'], item['avgHR'], item['calories'], Duration(seconds: item['durationSeconds']),
        )).toList();
      });
    }
  }

  void _decodeHR(List<int> data) {
    if (data.isEmpty) return;
    int hr = (data[0] & 0x01) == 0 ? data[1] : (data[2] << 8) | data[1];
    if (mounted && hr > 0) {
      setState(() {
        _heartRate = hr;
        if (_isWorkingOut) {
          _timeCounter += 1;
          _hrSpots.add(FlSpot(_timeCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 100) _hrSpots.removeAt(0);
          _avgHeartRate = (_hrSpots.map((e) => e.y).reduce((a, b) => a + b) / _hrSpots.length).toInt();
          if (_heartRate >= 100) {
            _calories += (_heartRate * 0.012 * (1/60));
          }
        }
      });
    }
  }

  Future<void> _connectWatch() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true, 
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4), 
      builder: (c) => Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const Padding(padding: EdgeInsets.all(15), child: Text("워치 검색 결과", style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(
            child: StreamBuilder<List<ScanResult>>(
              stream: FlutterBluePlus.scanResults,
              builder: (c, s) {
                final res = (s.data ?? []).where((r) => r.device.platformName.isNotEmpty).toList();
                if (res.isEmpty) return const Center(child: Text("주변 장치를 찾는 중...", style: TextStyle(fontSize: 12, color: Colors.white38)));
                return ListView.builder(
                  itemCount: res.length,
                  itemBuilder: (c, i) => ListTile(
                    leading: const Icon(Icons.watch, color: Colors.cyanAccent),
                    title: Text(res[i].device.platformName, style: const TextStyle(fontSize: 14)),
                    onTap: () async {
                      await res[i].device.connect();
                      _setupDevice(res[i].device);
                      Navigator.pop(context);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _setupDevice(BluetoothDevice device) async {
    setState(() { _isWatchConnected = true; });
    List<BluetoothService> services = await device.discoverServices();
    for (var s in services) { if (s.uuid == Guid("180D")) { for (var c in s.characteristics) { if (c.uuid == Guid("2A37")) { await c.setNotifyValue(true); c.lastValueStream.listen(_decodeHR); } } } }
  }

  void _toggleWorkout() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => _duration += const Duration(seconds: 1)));
      } else {
        _workoutTimer?.cancel();
      }
    });
  }

  void _resetWorkout() {
    if (_isWorkingOut) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동을 먼저 중지해주세요."), duration: Duration(seconds: 1)));
      return;
    }
    setState(() { _duration = Duration.zero; _calories = 0.0; _avgHeartRate = 0; _hrSpots = []; _timeCounter = 0; _heartRate = 0; });
  }

  void _saveRecord() async {
    if (_duration == Duration.zero) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 기록이 없습니다!")));
      return;
    }
    String date = DateFormat('M/d(E)', 'ko_KR').format(DateTime.now());
    setState(() { _records.insert(0, WorkoutRecord(date, _avgHeartRate, _calories, _duration)); });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workout_records', jsonEncode(_records.map((r) => {'date': r.date, 'avgHR': r.avgHR, 'calories': r.calories, 'durationSeconds': r.duration.inSeconds}).toList()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("기록이 저장되었습니다!")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Opacity(opacity: 0.4, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s)=>Container()))),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text('오버 더 바이크 핏', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                const SizedBox(height: 10),
                _smallRoundedBtn(_isWatchConnected ? "워치 연결됨" : "워치 연결하기", _isWatchConnected ? Colors.cyanAccent : Colors.white, _connectWatch),
                
                Container(
                  height: 45, width: double.infinity, margin: const EdgeInsets.symmetric(horizontal: 60, vertical: 15),
                  child: _hrSpots.isEmpty 
                    ? const Center(child: Text("심박수 대기...", style: TextStyle(fontSize: 9, color: Colors.white24)))
                    : LineChart(LineChartData(
                        gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false),
                        lineBarsData: [LineChartBarData(spots: _hrSpots, isCurved: true, color: Colors.cyanAccent, barWidth: 2, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: Colors.cyanAccent.withOpacity(0.1)))],
                      )),
                ),

                const Spacer(),
                
                // 📊 데이터 배너 (기존의 0.5배 확대 사이즈)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 25),
                  padding: const EdgeInsets.symmetric(vertical: 22), 
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white24, width: 1.2)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _modestStat("현재심박", "$_heartRate", Colors.cyanAccent),
                      _modestStat("평균심박", "$_avgHeartRate", Colors.redAccent),
                      _modestStat("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
                      _modestStat("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent),
                    ],
                  ),
                ),

                const Spacer(),

                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _rectBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작/정지", _toggleWorkout),
                      const SizedBox(width: 15),
                      _rectBtn(Icons.refresh, "리셋", _resetWorkout),
                      const SizedBox(width: 15),
                      _rectBtn(Icons.save, "저장", _saveRecord),
                      const SizedBox(width: 15),
                      _rectBtn(Icons.bar_chart, "기록보기", () {
                        Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records)));
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallRoundedBtn(String t, Color c, VoidCallback tap) => GestureDetector(onTap: tap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withOpacity(0.5))), child: Text(t, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold))));
  Widget _modestStat(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70)), const SizedBox(height: 4), Text(v, style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: c))]);
  Widget _rectBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, behavior: HitTestBehavior.opaque, child: Container(width: 60, height: 60, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)), child: Icon(i, color: Colors.white, size: 24))), const SizedBox(height: 8), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white))]);
}

// 2. 기록 보기 화면 클래스 (이 부분이 빠져서 오류가 났었습니다)
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  const HistoryScreen({Key? key, required this.records}) : super(key: key);
  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  void _deleteRecord(int index) async {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("기록 삭제"),
        content: const Text("이 운동 기록을 삭제하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
          TextButton(onPressed: () async {
            setState(() { widget.records.removeAt(index); });
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('workout_records', jsonEncode(widget.records.map((r) => {'date': r.date, 'avgHR': r.avgHR, 'calories': r.calories, 'durationSeconds': r.duration.inSeconds}).toList()));
            Navigator.pop(context);
          }, child: const Text("삭제", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("운동 리포트"), backgroundColor: Colors.transparent),
      body: widget.records.isEmpty
          ? const Center(child: Text("저장된 기록이 없습니다."))
          : ListView.builder(
              itemCount: widget.records.length,
              itemBuilder: (c, i) {
                final r = widget.records[i];
                return ListTile(
                  onLongPress: () => _deleteRecord(i),
                  leading: const Icon(Icons.directions_bike, color: Colors.cyanAccent),
                  title: Text("${r.date} 운동"),
                  subtitle: Text("${r.duration.inMinutes}분 | 평균 ${r.avgHR}BPM"),
                  trailing: Text("${r.calories.toStringAsFixed(1)}kcal", style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                );
              },
            ),
    );
  }
}
