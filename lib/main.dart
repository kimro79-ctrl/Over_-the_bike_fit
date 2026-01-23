import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 💡 세로 화면 고정
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await initializeDateFormatting('ko_KR', null);
  runApp(const BikeFitApp());
}

class WorkoutRecord {
  final String id;
  final String date;
  final int avgHR;
  final double calories;
  final Duration duration;
  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration);
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
          item['id'] ?? DateTime.now().toString(),
          item['date'], item['avgHR'], item['calories'], Duration(seconds: item['durationSeconds']),
        )).toList();
      });
    }
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workout_records', jsonEncode(_records.map((r) => {
      'id': r.id, 'date': r.date, 'avgHR': r.avgHR, 'calories': r.calories, 'durationSeconds': r.duration.inSeconds
    }).toList()));
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
          
          // 💡 칼로리 계산: 심박수 95 이상일 때만 작동
          if (_heartRate >= 95) {
            _calories += (95 * 0.012 * (1/60));
          }
        }
      });
    }
  }

  void _toggleWorkout() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() {
          _duration += const Duration(seconds: 1);
          if (_heartRate >= 95) {
            _calories += (95 * 0.012 * (1/60));
          }
        }));
      } else {
        _workoutTimer?.cancel();
      }
    });
  }

  void _resetWorkout() {
    if (_isWorkingOut) return;
    setState(() { _duration = Duration.zero; _calories = 0.0; _avgHeartRate = 0; _hrSpots = []; _timeCounter = 0; _heartRate = 0; });
  }

  void _saveRecord() async {
    if (_duration.inSeconds < 1) return;
    String dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    setState(() { _records.insert(0, WorkoutRecord(DateTime.now().toString(), dateStr, _avgHeartRate, _calories, _duration)); });
    await _saveToPrefs();
  }

  Future<void> _connectWatch() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => StreamBuilder<List<ScanResult>>(
        stream: FlutterBluePlus.scanResults,
        builder: (c, s) {
          final res = (s.data ?? []).where((r) => r.device.platformName.isNotEmpty || r.advertisementData.localName.isNotEmpty).toList();
          return Column(
            children: [
              const Padding(padding: EdgeInsets.all(15), child: Text("연결할 기기 선택", style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(
                child: ListView.builder(
                  itemCount: res.length,
                  itemBuilder: (c, i) {
                    final name = res[i].device.platformName.isEmpty ? res[i].advertisementData.localName : res[i].device.platformName;
                    return ListTile(
                      leading: const Icon(Icons.watch, color: Colors.greenAccent),
                      title: Text(name, style: const TextStyle(color: Colors.white)),
                      subtitle: Text(res[i].device.remoteId.toString(), style: const TextStyle(fontSize: 10, color: Colors.white54)),
                      onTap: () async {
                        await res[i].device.connect();
                        _setupDevice(res[i].device);
                        Navigator.pop(context);
                      },
                    );
                  }
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _setupDevice(BluetoothDevice device) async {
    setState(() { _isWatchConnected = true; });
    List<BluetoothService> services = await device.discoverServices();
    for (var s in services) {
      if (s.uuid == Guid("180D")) {
        for (var c in s.characteristics) {
          if (c.uuid == Guid("2A37")) {
            await c.setNotifyValue(true);
            c.lastValueStream.listen(_decodeHR);
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Opacity(opacity: 0.6, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s)=>Container(color: Colors.black)))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 30),
                  // 💡 타이틀: 가늘게 수정
                  const Text('Over the bike fit', 
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w300, color: Colors.white, letterSpacing: 1.0)),
                  
                  const SizedBox(height: 20),
                  
                  // 💡 스마트워치 연결 버튼: 약한 네온
                  GestureDetector(
                    onTap: _connectWatch,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.greenAccent.withOpacity(0.5), width: 1.2),
                        boxShadow: [
                          BoxShadow(color: Colors.greenAccent.withOpacity(0.1), blurRadius: 4, spreadRadius: 1),
                        ],
                      ),
                      child: Text(
                        _isWatchConnected ? "스마트워치 연결됨" : "스마트워치 연결",
                        style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  SizedBox(
                    height: 50, width: double.infinity,
                    child: LineChart(LineChartData(
                      gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false),
                      lineBarsData: [LineChartBarData(spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots, isCurved: true, color: Colors.greenAccent, barWidth: 2, dotData: const FlDotData(show: false))])),
                  ),

                  // 💡 모든 UI를 아래로 밀어줌
                  const Spacer(),
                  
                  // 💡 데이터 배너: 버튼 위 + 1/3 축소 + 투명도 0.4
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16), 
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4), 
                      borderRadius: BorderRadius.circular(20), 
                      border: Border.all(color: Colors.white.withOpacity(0.05), width: 1)
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _statItem("심박수", "$_heartRate", Colors.greenAccent),
                        _statItem("평균", "$_avgHeartRate", Colors.redAccent),
                        _statItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
                        _statItem("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 💡 최하단 버튼 영역
                  Padding(
                    padding: const EdgeInsets.only(bottom: 30),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _rectBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작/정지", _toggleWorkout),
                        const SizedBox(width: 15),
                        _rectBtn(Icons.refresh, "리셋", _resetWorkout),
                        const SizedBox(width: 15),
                        _rectBtn(Icons.save, "저장", _saveRecord),
                        const SizedBox(width: 15),
                        _rectBtn(Icons.bar_chart, "기록", () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, onSync: _saveToPrefs)));
                          setState(() {});
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String l, String v, Color c) => Column(children: [
    Text(l, style: const TextStyle(fontSize: 11, color: Colors.white70)),
    const SizedBox(height: 4),
    Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c)), 
  ]);
  
  Widget _rectBtn(IconData i, String l, VoidCallback t) => Column(children: [
    GestureDetector(onTap: t, behavior: HitTestBehavior.opaque, child: Container(width: 58, height: 58, decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white12)), child: Icon(i, color: Colors.white, size: 24))),
    const SizedBox(height: 6),
    Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70))
  ]);
}

class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final Function onSync;
  const HistoryScreen({Key? key, required this.records, required this.onSync}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}
class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  @override
  Widget build(BuildContext context) {
    final filtered = _selectedDay == null ? widget.records : widget.records.where((r) => r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).toList();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text("운동 히스토리", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w300)), backgroundColor: Colors.white, iconTheme: const IconThemeData(color: Colors.black), elevation: 0),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2024, 1, 1), lastDay: DateTime.utc(2030, 12, 31), focusedDay: _focusedDay, locale: 'ko_KR',
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
            calendarStyle: const CalendarStyle(defaultTextStyle: TextStyle(color: Colors.black), weekendTextStyle: TextStyle(color: Colors.red), selectedDecoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle)),
            headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true, titleTextStyle: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (c, i) => ListTile(
                leading: const Icon(Icons.directions_bike, color: Colors.blue),
                title: Text("${filtered[i].date} 라이딩", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                trailing: Text("${filtered[i].calories.toStringAsFixed(1)}kcal", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
