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

  BluetoothDevice? _targetDevice;
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
          item['date'],
          item['avgHR'],
          item['calories'],
          Duration(seconds: item['durationSeconds']),
        )).toList();
      });
    }
  }

  Future<void> _saveRecordsToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> recordList = _records.map((r) => {
      'date': r.date, 'avgHR': r.avgHR, 'calories': r.calories, 'durationSeconds': r.duration.inSeconds,
    }).toList();
    await prefs.setString('workout_records', jsonEncode(recordList));
  }

  void _resetWorkout() {
    if (_isWorkingOut) return;
    setState(() {
      _duration = Duration.zero; _calories = 0.0; _avgHeartRate = 0; _hrSpots = []; _timeCounter = 0;
    });
    HapticFeedback.mediumImpact();
  }

  Future<void> _connectWatch() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StreamBuilder<List<ScanResult>>(
        stream: FlutterBluePlus.scanResults,
        builder: (context, snapshot) {
          final results = (snapshot.data ?? []).where((r) => r.device.platformName.isNotEmpty).toList();
          return Column(
            children: [
              const Padding(padding: EdgeInsets.all(15), child: Text("연결할 워치 선택")),
              Expanded(child: ListView.builder(itemCount: results.length, itemBuilder: (context, index) {
                final r = results[index];
                return ListTile(
                  leading: const Icon(Icons.watch, color: Colors.cyanAccent),
                  title: Text(r.device.platformName),
                  onTap: () async {
                    await r.device.connect(); _setupDevice(r.device); Navigator.pop(context);
                  }
                );
              })),
            ],
          );
        },
      ),
    );
  }

  void _setupDevice(BluetoothDevice device) async {
    setState(() { _targetDevice = device; _isWatchConnected = true; });
    List<BluetoothService> services = await device.discoverServices();
    for (var service in services) {
      if (service.uuid == Guid("180D")) {
        for (var char in service.characteristics) {
          if (char.uuid == Guid("2A37")) {
            await char.setNotifyValue(true);
            char.lastValueStream.listen((value) => _decodeHR(value));
          }
        }
      }
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
          if (_hrSpots.length > 120) _hrSpots.removeAt(0);
          _avgHeartRate = (_hrSpots.map((e) => e.y).reduce((a, b) => a + b) / _hrSpots.length).toInt();
          
          if (_heartRate >= 100) {
            _calories += (_heartRate * 0.012 * (1/60)); 
          }
        }
      });
    }
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

  void _saveRecord() async {
    if (_duration == Duration.zero) return;
    String formattedDate = DateFormat('M/d(E)', 'ko_KR').format(DateTime.now());
    setState(() { _records.insert(0, WorkoutRecord(formattedDate, _avgHeartRate, _calories, _duration)); });
    await _saveRecordsToStorage();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("기록이 저장되었습니다.")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 🖼️ 배경 이미지 설정
          Positioned.fill(
            child: Opacity(
              opacity: 0.5,
              child: Image.asset(
                'assets/background.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(color: Colors.black),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                const SizedBox(height: 15),
                GestureDetector(
                  onTap: _isWatchConnected ? null : _connectWatch,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20), border: Border.all(color: _isWatchConnected ? Colors.cyanAccent : Colors.white24)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.watch, size: 16, color: _isWatchConnected ? Colors.cyanAccent : Colors.white),
                      const SizedBox(width: 8),
                      Text(_isWatchConnected ? "연결 완료" : "워치 연결하기", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),
                const Spacer(),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 25),
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white12)),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      _statItem("현재 심박수", "$_heartRate", Colors.cyanAccent),
                      _statItem("평균 심박수", "$_avgHeartRate", Colors.redAccent),
                    ]),
                    const SizedBox(height: 30),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      _statItem("칼로리 소모", _calories.toStringAsFixed(1), Colors.orangeAccent),
                      _statItem("운동 시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent),
                    ]),
                  ]),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작/중지", _toggleWorkout),
                    _actionBtn(Icons.refresh, "리셋", _resetWorkout),
                    _actionBtn(Icons.file_upload_outlined, "기록저장", _saveRecord),
                    _actionBtn(Icons.calendar_month, "기록보기", () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryScreen(records: _records)));
                    }),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) => Column(children: [
    Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
    Text(value, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color)),
  ]);

  Widget _actionBtn(IconData icon, String label, VoidCallback tap) => Column(children: [
    GestureDetector(onTap: tap, child: Container(width: 60, height: 60, decoration: BoxDecoration(color: Colors.white10, shape: BoxShape.circle, border: Border.all(color: Colors.white24)), child: Icon(icon, color: Colors.white))),
    const SizedBox(height: 8),
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70)),
  ]);
}

class HistoryScreen extends StatelessWidget {
  final List<WorkoutRecord> records;
  const HistoryScreen({Key? key, required this.records}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    DateTime now = DateTime.now();
    int daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);
    Set<int> workoutDays = records.map((r) {
      try { return int.parse(r.date.split('/')[1].split('(')[0]); } catch (e) { return -1; }
    }).toSet();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("운동 기록"), backgroundColor: Colors.transparent),
      body: SingleChildScrollView(
        child: Column(children: [
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
            child: Column(children: [
              Text("${now.month}월 활동 달력", style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
                itemCount: daysInMonth,
                itemBuilder: (context, index) {
                  int day = index + 1;
                  bool isDone = workoutDays.contains(day);
                  return Column(children: [
                    Text("$day", style: TextStyle(fontSize: 12, color: isDone ? Colors.cyanAccent : Colors.white38)),
                    if (isDone) Container(margin: const EdgeInsets.only(top: 2), width: 5, height: 5, decoration: const BoxDecoration(color: Colors.cyanAccent, shape: BoxShape.circle)),
                  ]);
                },
              ),
            ]),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: records.length,
            itemBuilder: (context, index) {
              final r = records[index];
              return ListTile(
                leading: const Icon(Icons.directions_bike, color: Colors.cyanAccent),
                title: Text("${r.duration.inMinutes}분 운동 (${r.avgHR} BPM)"),
                subtitle: Text(r.date),
                trailing: Text("${r.calories.toInt()} kcal", style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
              );
            },
          ),
        ]),
      ),
    );
  }
}
