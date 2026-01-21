import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const BikeFitApp());
  await Future.delayed(const Duration(seconds: 3));
  FlutterNativeSplash.remove();
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
  int elapsedSeconds = 0;
  int targetMinutes = 20;
  bool isRunning = false;
  String watchStatus = "탭하여 설정에서 워치 연결";
  Timer? workoutTimer;
  List<Map<String, dynamic>> workoutLogs = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('workout_history');
    if (data != null) setState(() => workoutLogs = List<Map<String, dynamic>>.from(json.decode(data)));
  }

  Future<void> _saveLog() async {
    if (elapsedSeconds < 5) return;
    final prefs = await SharedPreferences.getInstance();
    final log = {"date": "${DateTime.now().month}/${DateTime.now().day}", "time": "${elapsedSeconds ~/ 60}분 ${elapsedSeconds % 60}초", "bpm": bpm > 0 ? "$bpm" : "-"};
    workoutLogs.insert(0, log);
    await prefs.setString('workout_history', json.encode(workoutLogs));
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("기록 저장 완료!")));
  }

  Future<void> _handleWatchConnection() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    await FlutterBluePlus.turnOn(); 
    setState(() => watchStatus = "설정 확인 중...");
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => ListView.builder(
        itemCount: workoutLogs.length,
        itemBuilder: (context, i) => ListTile(
          title: Text(workoutLogs[i]['date']),
          subtitle: Text("시간: ${workoutLogs[i]['time']} | 심박수: ${workoutLogs[i]['bpm']}"),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/background.png"), fit: BoxFit.cover)),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(15),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const SizedBox(width: 40),
                const Text("OVER THE BIKE FIT", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.history, color: Colors.white), onPressed: _showHistory),
              ]),
            ),
            GestureDetector(
              onTap: _handleWatchConnection,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                decoration: BoxDecoration(border: Border.all(color: Colors.cyan), borderRadius: BorderRadius.circular(20)),
                child: Text(watchStatus, style: const TextStyle(color: Colors.cyan, fontSize: 13)),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(25),
              decoration: const BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  Column(children: [
                    const Text("운동시간", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text("${elapsedSeconds ~/ 60}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", style: const TextStyle(fontSize: 28, color: Colors.redAccent)),
                  ]),
                  Column(children: [
                    const Text("목표설정", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Row(children: [
                      IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => setState(() => targetMinutes--)),
                      Text("$targetMinutes분", style: const TextStyle(fontSize: 22)),
                      IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setState(() => targetMinutes++)),
                    ]),
                  ]),
                ]),
                const SizedBox(height: 30),
                Row(children: [
                  Expanded(child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: isRunning ? Colors.grey : Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 15)),
                    onPressed: () {
                      setState(() {
                        isRunning = !isRunning;
                        if (isRunning) workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++));
                        else workoutTimer?.cancel();
                      });
                    }, child: Text(isRunning ? "정지" : "시작"))),
                  const SizedBox(width: 15),
                  Expanded(child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 15)),
                    onPressed: _saveLog, child: const Text("저장"))),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
