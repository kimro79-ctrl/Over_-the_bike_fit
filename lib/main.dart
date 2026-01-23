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
  
  // 블루투스 스캔 데이터
  List<ScanResult> _filteredResults = [];
  StreamSubscription? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _loadRecords();
    _attemptAutoConnect();
  }

  // 💡 [기능 삽입] UI는 유지하고 팝업 로직만 실행
  void _showDeviceScanPopup() async {
    if (_isWatchConnected) return;

    // 블루투스 및 위치 권한 요청
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses.values.every((s) => s.isGranted)) {
      _filteredResults.clear();
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1A1A1A), // 다크 모드 일관성 유지
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
                if (mounted) {
                  setModalState(() {
                    // 기기 이름이 있고 워치/밴드 키워드가 있거나 심박수 서비스 제공 기기만 나열
                    _filteredResults = results.where((r) => 
                      r.device.platformName.isNotEmpty && 
                      (r.device.platformName.contains("Watch") || 
                       r.device.platformName.contains("Band") || 
                       r.advertisementData.serviceUuids.contains(Guid("180D")))
                    ).toList();
                  });
                }
              });

              return Container(
                padding: const EdgeInsets.all(20),
                height: 350,
                child: Column(
                  children: [
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 20),
                    const Text("등록 가능한 기기", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    Expanded(
                      child: _filteredResults.isEmpty 
                        ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
                        : ListView.builder(
                            itemCount: _filteredResults.length,
                            itemBuilder: (context, index) {
                              final data = _filteredResults[index];
                              return ListTile(
                                leading: const Icon(Icons.watch_rounded, color: Colors.greenAccent),
                                title: Text(data.device.platformName, style: const TextStyle(color: Colors.white)),
                                subtitle: const Text("터치하여 연결", style: TextStyle(color: Colors.white38, fontSize: 11)),
                                onTap: () {
                                  Navigator.pop(context);
                                  _connectToDevice(data.device);
                                },
                              );
                            },
                          ),
                    ),
                  ],
                ),
              );
            }
          );
        },
      ).whenComplete(() {
        FlutterBluePlus.stopScan();
        _scanSubscription?.cancel();
      });
    }
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      _setupDevice(device);
    } catch (e) {
      _showToast("연결 실패");
    }
  }

  void _setupDevice(BluetoothDevice device) async {
    setState(() { _isWatchConnected = true; });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_watch_id', device.remoteId.toString());
    
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

  void _decodeHR(List<int> data) {
    if (data.isEmpty) return;
    int hr = (data[0] & 0x01) == 0 ? data[1] : (data[2] << 8) | data[1];
    if (mounted && hr > 0) {
      setState(() {
        _heartRate = hr;
        if (_isWorkingOut) {
          _timeCounter += 1;
          _hrSpots.add(FlSpot(_timeCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 50) _hrSpots.removeAt(0);
          _avgHeartRate = (_hrSpots.map((e) => e.y).reduce((a, b) => a + b) / _hrSpots.length).toInt();
        }
      });
    }
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

  Future<void> _attemptAutoConnect() async {
    final prefs = await SharedPreferences.getInstance();
    String? lastId = prefs.getString('last_watch_id');
    if (lastId != null) {
      BluetoothDevice device = BluetoothDevice.fromId(lastId);
      try {
        await device.connect(autoConnect: true).timeout(const Duration(seconds: 5));
        _setupDevice(device);
      } catch (e) { debugPrint("자동 연결 실패"); }
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: Opacity(opacity: 0.5, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s)=>Container(color: Colors.black)))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  const Text('OVER THE BIKE FIT', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.5)),
                  const SizedBox(height: 15),
                  _connectButton(), // 💡 UI는 그대로, 클릭 시 팝업 실행
                  const SizedBox(height: 25),
                  _chartArea(),
                  const Spacer(),
                  _dataBanner(),
                  const SizedBox(height: 30),
                  _controlButtons(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 기존 위젯 UI 코드 유지 ---

  Widget _connectButton() => GestureDetector(
    onTap: _showDeviceScanPopup, 
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.greenAccent, width: 1.2)),
      child: Text(_isWatchConnected ? "연결됨" : "워치 연결", style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
    ),
  );

  Widget _chartArea() => SizedBox(
    height: 60,
    child: LineChart(LineChartData(
      gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false),
      lineBarsData: [LineChartBarData(spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots, isCurved: true, color: Colors.greenAccent, barWidth: 2, dotData: const FlDotData(show: false))])),
  );

  Widget _dataBanner() => Container(
    padding: const EdgeInsets.symmetric(vertical: 20),
    decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _statItem("심박수", "$_heartRate", Colors.greenAccent),
        _statItem("평균", "$_avgHeartRate", Colors.redAccent),
        _statItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
        _statItem("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent),
      ],
    ),
  );

  Widget _statItem(String l, String v, Color c) => Column(children: [
    Text(l, style: const TextStyle(fontSize: 11, color: Colors.white60)),
    const SizedBox(height: 6),
    Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c)), 
  ]);

  Widget _controlButtons() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작/정지", () {
        setState(() {
          _isWorkingOut = !_isWorkingOut;
          if (_isWorkingOut) {
            _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() {
              _duration += const Duration(seconds: 1);
              if (_heartRate >= 95) _calories += (95 * 0.012 * (1/60));
            }));
          } else { _workoutTimer?.cancel(); }
        });
      }),
      const SizedBox(width: 15),
      _actionBtn(Icons.refresh, "리셋", () { if(!_isWorkingOut) setState((){_duration=Duration.zero;_calories=0.0;_avgHeartRate=0;_heartRate=0;_hrSpots=[];}); }),
      const SizedBox(width: 15),
      _actionBtn(Icons.save, "저장", () {
        if (_duration.inSeconds < 5) return;
        String dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        setState(() { _records.insert(0, WorkoutRecord(DateTime.now().toString(), dateStr, _avgHeartRate, _calories, _duration)); });
        _saveToPrefs();
        _showToast("저장되었습니다.");
      }),
      const SizedBox(width: 15),
      _actionBtn(Icons.calendar_month, "기록", () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, onSync: _saveToPrefs)))),
    ],
  );

  Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(children: [
    GestureDetector(onTap: t, child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(15)), child: Icon(i, color: Colors.white, size: 24))),
    const SizedBox(height: 6),
    Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70))
  ]);
}

// HistoryScreen 클래스 생략 (기존 디자인 동일 유지)
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
    final filtered = widget.records.where((r) => _selectedDay == null || r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(title: const Text("운동 히스토리", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: Colors.white, elevation: 0, iconTheme: const IconThemeData(color: Colors.black)),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2024, 1, 1), lastDay: DateTime.utc(2030, 12, 31), focusedDay: _focusedDay, locale: 'ko_KR',
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
            eventLoader: (day) {
              String formatted = DateFormat('yyyy-MM-dd').format(day);
              return widget.records.where((r) => r.date == formatted).toList();
            },
            calendarStyle: const CalendarStyle(defaultTextStyle: TextStyle(color: Colors.black), markerDecoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle), selectedDecoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle)),
            headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true, titleTextStyle: TextStyle(color: Colors.black, fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          const Divider(thickness: 1, height: 1),
          Expanded(
            child: filtered.isEmpty 
              ? const Center(child: Text("기록이 없습니다.", style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 10),
                  itemCount: filtered.length,
                  itemBuilder: (c, i) {
                    final r = filtered[i];
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
                      child: InkWell(
                        onLongPress: () {
                          showDialog(context: context, builder: (context) => AlertDialog(
                            backgroundColor: Colors.white,
                            title: const Text("기록 삭제", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                            content: const Text("이 기록을 삭제하시겠습니까?", style: TextStyle(color: Colors.black87)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소", style: TextStyle(color: Colors.grey))),
                              TextButton(onPressed: () {
                                setState(() { widget.records.removeWhere((rec) => rec.id == r.id); });
                                widget.onSync();
                                Navigator.pop(context);
                              }, child: const Text("삭제", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                            ],
                          ));
                        },
                        borderRadius: BorderRadius.circular(15),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.directions_bike, color: Colors.white, size: 20)),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(r.date, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 15)),
                                  const SizedBox(height: 4),
                                  Text("${r.duration.inMinutes}분 운동 / 평균 ${r.avgHR}bpm", style: const TextStyle(color: Colors.black54, fontSize: 12)),
                                ]),
                              ),
                              Text("${r.calories.toStringAsFixed(1)} kcal", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w900, fontSize: 16)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}
