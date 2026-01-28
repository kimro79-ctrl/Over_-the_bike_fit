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
[span_1](start_span)import 'package:table_calendar/table_calendar.dart';[span_1](end_span)

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await initializeDateFormatting('ko_KR', null);
  [span_2](start_span)runApp(const BikeFitApp());[span_2](end_span)
}

class WorkoutRecord {
  final String id;
  final String date;
  final int avgHR;
  final double calories;
  final Duration duration;
  [span_3](start_span)WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration);[span_3](end_span)

  Map<String, dynamic> toJson() => {
    'id': id, 'date': date, 'avgHR': avgHR, 'calories': calories, 'durationSeconds': duration.inSeconds
  };
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: Colors.black),
      home: const WorkoutScreen(),
    [span_4](start_span));[span_4](end_span)
  }
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  [span_5](start_span)@override _WorkoutScreenState createState() => _WorkoutScreenState();[span_5](end_span)
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0, _avgHeartRate = 0;
  [span_6](start_span)double _calories = 0.0, _goalCalories = 300.0;[span_6](end_span)
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  bool _isWorkingOut = false, _isWatchConnected = false;
  [span_7](start_span)List<FlSpot> _hrSpots = [];[span_7](end_span)
  double _timeCounter = 0;
  List<WorkoutRecord> _records = [];
  List<ScanResult> _filteredResults = [];
  StreamSubscription? _scanSubscription;

  @override
  void initState() { super.initState(); _loadInitialData(); [span_8](start_span)}

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _goalCalories = prefs.getDouble('goal_calories') ?? 300.0;
      final String? res = prefs.getString('workout_records');
      if (res != null) {
        final List<dynamic> decoded = jsonDecode(res);
        _records = decoded.map((item) => WorkoutRecord(
          item['id'] ?? DateTime.now().toString(), 
          item['date'], 
          item['avgHR'], 
          (item['calories'] as num).toDouble(),
          Duration(seconds: item['durationSeconds'] ?? 0)
        )).toList();
      }
    });[span_8](end_span)
  }

  // --- 워치 스캔 팝업 (강화된 스캔 로직 적용) ---
  void _showDeviceScanPopup() async {
    if (_isWatchConnected) return;
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    _[span_9](start_span)filteredResults.clear();[span_9](end_span)

    // 갤럭시 워치 검색을 위해 스캔 모드를 lowLatency(고성능)로 설정
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      androidUsesFineLocation: true,
      androidScanMode: AndroidScanMode.lowLatency,
    [span_10](start_span));[span_10](end_span)

    showModalBottomSheet(
      context: context, 
      backgroundColor: const Color(0xFF1E1E1E), 
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))), 
      builder: (context) => StatefulBuilder(builder: (context, setModalState) {
        _scanSubscription = FlutterBluePlus.onScanResults.listen((results) { 
          if (mounted) setModalState(() { _filteredResults = results; }); 
        });
        return Container(padding: const EdgeInsets.all(20), height: MediaQuery.of(context).size.height * 0.4, child: Column(children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text("워치 검색", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Expanded(child: ListView.builder(itemCount: _filteredResults.length, itemBuilder: (context, index) {
            final d = _filteredResults[index].device;
            return ListTile(
              leading: const Icon(Icons.watch, color: Colors.blueAccent), 
              title: Text(d.platformName.isEmpty ? "기기 (${d.remoteId})" : d.platformName), 
              onTap: () { Navigator.pop(context); _connectToDevice(d); }
            [span_11](start_span));[span_11](end_span)
          })) 
        ]));
      [span_12](start_span)})).whenComplete(() { FlutterBluePlus.stopScan(); _scanSubscription?.cancel(); });[span_12](end_span)
  }

  void _connectToDevice(BluetoothDevice device) async { try { await device.connect(); _setupDevice(device); } catch (e) { _showToast("연결 실패"); [span_13](start_span)} }[span_13](end_span)
  
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
  [span_14](start_span)}

  void _decodeHR(List<int> data) {
    if (data.isEmpty) return;
    int hr = (data[0] & 0x01) == 0 ? data[1] : (data[2] << 8) | data[1];[span_14](end_span)
    if (mounted && hr > 0) {
      setState(() {
        _heartRate = hr;
        if (_isWorkingOut) {
          _timeCounter += 1;
          _hrSpots.add(FlSpot(_timeCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 50) _hrSpots.removeAt(0);
          _avgHeartRate = (_hrSpots.map((e) => e.y).reduce((a, b) => a + b) / _hrSpots.length).toInt();
        }
      [span_15](start_span)});[span_15](end_span)
    }
  }

  void _showGoalSettings() {
    final controller = TextEditingController(text: _goalCalories.toInt().toString());
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF1E1E1E), isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(padding: const EdgeInsets.all(25), height: 260, child: Column(children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 25),
          [span_16](start_span)const Text("목표 칼로리 설정", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),[span_16](end_span)
          const SizedBox(height: 20),
          TextField(controller: controller, keyboardType: TextInputType.number, autofocus: true, textAlign: TextAlign.center, style: const TextStyle(color: Colors.greenAccent, fontSize: 36, fontWeight: FontWeight.bold), decoration: const InputDecoration(suffixText: "kcal", suffixStyle: TextStyle(color: Colors.white38, fontSize: 16))),
          const Spacer(),
          SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), padding: const EdgeInsets.symmetric(vertical: 16)), onPressed: () async {
            setState(() { _goalCalories = double.tryParse(controller.text) ?? 300.0; });
            (await SharedPreferences.getInstance()).setDouble('goal_calories', _goalCalories);
            [span_17](start_span)Navigator.pop(context);[span_17](end_span)
          }, child: const Text("설정 완료", style: TextStyle(fontWeight: FontWeight.bold)))),
        ])),
      ),
    [span_18](start_span));[span_18](end_span)
  }

  void _showToast(String msg) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 1))); [span_19](start_span)}

  @override
  Widget build(BuildContext context) {
    double progress = (_calories / _goalCalories).clamp(0.0, 1.0);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        Positioned.fill(child: Opacity(opacity: 0.8, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s)=>Container(color: Colors.black)))),
        SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(children: [
                const SizedBox(height: 40),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.5)),
                  _connectButton(),
                ]),[span_19](end_span)
                const SizedBox(height: 25),
                _chartArea(),
                const SizedBox(height: 100),
                GestureDetector(onTap: _showGoalSettings, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)), child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text("CALORIE GOAL", style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold)),
                    Text("${_calories.toInt()} / ${_goalCalories.toInt()} kcal", style: const TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  [span_20](start_span)]),[span_20](end_span)
                  const SizedBox(height: 10),
                  [span_21](start_span)ClipRRect(borderRadius: BorderRadius.circular(5), child: SizedBox(height: 10, child: LinearProgressIndicator(value: progress, backgroundColor: Colors.white12, color: Colors.greenAccent))),[span_21](end_span)
                ]))),
                const SizedBox(height: 20),
                _dataBanner(),
                const SizedBox(height: 30),
                _controlButtons(),
                [span_22](start_span)const SizedBox(height: 40),[span_22](end_span)
              ]),
            ),
          ),
        ),
      ]),
    [span_23](start_span));[span_23](end_span)
  }

  [span_24](start_span)Widget _connectButton() => GestureDetector(onTap: _showDeviceScanPopup, child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.greenAccent)), child: Text(_isWatchConnected ? "연결됨" : "워치 연결", style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold))));[span_24](end_span)
  [span_25](start_span)Widget _chartArea() => SizedBox(height: 60, child: LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots, isCurved: true, color: Colors.greenAccent, barWidth: 2, dotData: const FlDotData(show: false))])));[span_25](end_span)
  [span_26](start_span)Widget _dataBanner() => Container(padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_statItem("심박수", "$_heartRate", Colors.greenAccent), _statItem("평균", "$_avgHeartRate", Colors.redAccent), _statItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent), _statItem("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent)]));[span_26](end_span)
  [span_27](start_span)Widget _statItem(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)), const SizedBox(height: 6), Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c))]);[span_27](end_span)
  
  Widget _controlButtons() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    _actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작", () { 
      setState(() { 
        _isWorkingOut = !_isWorkingOut; 
        if (_isWorkingOut) { 
          _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
            setState(() { _duration += const Duration(seconds: 1); if (_heartRate >= 95) { _calories += 0.15; } }); 
          }); 
        } else { _workoutTimer?.cancel(); } 
      }); 
    [span_28](start_span)}),[span_28](end_span)
    const SizedBox(width: 15),
    _actionBtn(Icons.refresh, "리셋", () { 
      if(!_isWorkingOut) { setState((){ _duration=Duration.zero; _calories=0.0; _avgHeartRate=0; _heartRate=0; _hrSpots=[]; _timeCounter=0; }); _showToast("리셋되었습니다."); } 
      else { _showToast("운동 중엔 리셋 불가"); }
    }),
    const SizedBox(width: 15),
    _actionBtn(Icons.save, "저장", () async {
      [span_29](start_span)if (_isWorkingOut) { _showToast("일시정지 후 저장하세요."); return; }[span_29](end_span)
      if (_duration.inSeconds < 5) { _showToast("기록이 너무 짧습니다."); return; [span_30](start_span)}
      final newRec = WorkoutRecord(DateTime.now().toString(), DateFormat('yyyy-MM-dd').format(DateTime.now()), _avgHeartRate, _calories, _duration);
      setState(() { _records.insert(0, newRec); });
      final prefs = await SharedPreferences.getInstance();[span_30](end_span)
      await prefs.setString('workout_records', jsonEncode(_records.map((r) => r.toJson()).toList()));
      _[span_31](start_span)showToast("저장 완료!");[span_31](end_span)
    }),
    const SizedBox(width: 15),
    _actionBtn(Icons.calendar_month, "기록", () async {
      await Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, onSync: _loadInitialData)));
      _loadInitialData();
    }),
  [span_32](start_span)]);[span_32](end_span)
  
  [span_33](start_span)Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)), child: Icon(i, color: Colors.white, size: 24))), const SizedBox(height: 6), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70))]);[span_33](end_span)
}

class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final VoidCallback onSync;
  [span_34](start_span)const HistoryScreen({Key? key, required this.records, required this.onSync}) : super(key: key);[span_34](end_span)
  [span_35](start_span)@override _HistoryScreenState createState() => _HistoryScreenState();[span_35](end_span)
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  late List<WorkoutRecord> _currentRecords;

  @override
  void initState() { 
    super.initState(); 
    _currentRecords = List.from(widget.records); 
    _selectedDay = _focusedDay; 
  [span_36](start_span)}

  // 데이터 시각화: 그래프 팝업 (에러 수정됨)
  void _showGraphPopup(String title, int days, Color color) {
    final limit = DateTime.now().subtract(Duration(days: days));
    var filtered = _currentRecords.where((r) => DateTime.parse(r.date).isAfter(limit)).toList().reversed.toList();[span_36](end_span)
    double maxCal = filtered.isEmpty ? [span_37](start_span)100 : filtered.map((e) => e.calories).reduce((a, b) => a > b ? a : b);[span_37](end_span)
    
    showModalBottomSheet(context: context, backgroundColor: Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))), 
      builder: (context) => Container(height: 350, padding: const EdgeInsets.all(20), child: Column(children: [
        Text(title, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 20),
        Expanded(child: BarChart(BarChartData(
          maxY: maxCal * 1.5,
          barGroups: List.generate(filtered.length, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: filtered[i].calories, color: color, width: 16, borderRadius: BorderRadius.circular(4))])),
          // ✅ 빌드 에러 원인 수정: 최신 문법으로 변경
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => color.withOpacity(0.8),
            ),
          ),
          gridData: const FlGridData(show: false), 
          titlesData: const FlTitlesData(show: false), 
          borderData: FlBorderData(show: false), 
        [span_38](start_span)))),[span_38](end_span)
      ]))
    [span_39](start_span));[span_39](end_span)
  }

  @override
  Widget build(BuildContext context) {
    final dailyRecords = _currentRecords.where((r) => r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).toList();
    return Theme(
      data: ThemeData(brightness: Brightness.light),
      child: Scaffold(
        appBar: AppBar(
          title: const Text("기록 리포트"),
          actions: [
            IconButton(icon: const Icon(Icons.bar_chart), onPressed: () => _showGraphPopup("최근 7일 통계", 7, Colors.blueAccent)),
          ],
        [span_40](start_span)),[span_40](end_span)
        body: SingleChildScrollView(child: Column(children: [
          TableCalendar(
            locale: 'ko_KR', firstDay: DateTime(2024), lastDay: DateTime(2030), focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
          [span_41](start_span)),[span_41](end_span)
          const Divider(),
          ...dailyRecords.map((r) => ListTile(
            leading: const Icon(Icons.directions_bike, color: Colors.blueAccent),
            title: Text("${r.calories.toInt()} kcal 소모"), 
            subtitle: Text("운동 시간: ${r.duration.inMinutes}분 | 평균 심박수: ${r.avgHR} BPM")
          )).toList()
        [span_42](start_span)])),[span_42](end_span)
      ),
    );
  }
}
