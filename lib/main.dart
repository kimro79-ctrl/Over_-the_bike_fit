import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';

void main() => runApp(const BikeFitApp());

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
  int bpm = 98;
  int targetMinutes = 20;
  int elapsedSeconds = 0;
  bool isRunning = false;
  List<double> heartPoints = List.generate(50, (index) => 40.0);
  List<String> workoutHistory = []; // 운동 기록 저장소
  
  Timer? dataTimer;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    startSim();
  }

  void startSim() {
    dataTimer = Timer.periodic(const Duration(milliseconds: 150), (t) {
      if (mounted) {
        setState(() {
          bpm = 95 + Random().nextInt(15);
          heartPoints.add(Random().nextDouble() * 50); // 더 역동적인 변화
          heartPoints.removeAt(0);
        });
      }
    });
  }

  void toggleWorkout() {
    setState(() {
      isRunning = !isRunning;
      if (isRunning) {
        workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++));
      } else {
        workoutTimer?.cancel();
      }
    });
  }

  void saveRecord() {
    String record = "${DateTime.now().toString().split('.')[0]} | ${elapsedSeconds ~/ 60}분 ${elapsedSeconds % 60}초 완료";
    setState(() => workoutHistory.add(record));
    
    // 저장 후 리스트 화면으로 이동
    Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryScreen(history: workoutHistory)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/background.png"), fit: BoxFit.cover)),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Text("Over the Bike Fit", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w200)),
              
              // 슬림하고 세련된 그래프 박스
              Container(
                margin: const EdgeInsets.all(25),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.redAccent.withOpacity(0.3))),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.favorite, color: Colors.red, size: 20),
                      const SizedBox(width: 10),
                      Text("$bpm bpm", style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 15),
                    SizedBox(height: 70, width: double.infinity, child: CustomPaint(painter: SmoothWavePainter(heartPoints))),
                  ],
                ),
              ),

              const Spacer(),
              
              // 컨트롤부
              Container(
                padding: const EdgeInsets.all(30),
                decoration: const BoxDecoration(color: Colors.black90, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      Column(children: [const Text("운동시간", style: TextStyle(color: Colors.grey)), Text("${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", style: const TextStyle(fontSize: 28, color: Colors.redAccent))]),
                      Column(children: [const Text("목표시간", style: TextStyle(color: Colors.grey)), Row(children: [IconButton(icon: const Icon(Icons.remove), onPressed: () => setState(() => targetMinutes--)), Text("$targetMinutes분", style: const TextStyle(fontSize: 24)), IconButton(icon: const Icon(Icons.add), onPressed: () => setState(() => targetMinutes++))])]),
                    ]),
                    const SizedBox(height: 30),
                    Row(children: [
                      actionBtn(isRunning ? "정지" : "시작", isRunning ? Colors.orange : Colors.red, toggleWorkout),
                      const SizedBox(width: 10),
                      actionBtn("리셋", Colors.grey.shade800, () => setState(() => elapsedSeconds = 0)),
                      const SizedBox(width: 10),
                      actionBtn("저장", Colors.green, saveRecord),
                    ]),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget actionBtn(String txt, Color col, VoidCallback fn) => Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: col, padding: const EdgeInsets.symmetric(vertical: 15)), onPressed: fn, child: Text(txt)));
}

// 부드러운 곡선 그래프를 그리는 Painter
class SmoothWavePainter extends CustomPainter {
  final List<double> points;
  SmoothWavePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.redAccent..strokeWidth = 2.5..style = PaintingStyle.stroke;
    final path = Path();
    final xStep = size.width / (points.length - 1);
    
    path.moveTo(0, size.height - points[0]);
    for (int i = 0; i < points.length - 1; i++) {
      var x1 = i * xStep;
      var y1 = size.height - points[i];
      var x2 = (i + 1) * xStep;
      var y2 = size.height - points[i + 1];
      path.bezierTo(x1 + (xStep / 2), y1, x1 + (xStep / 2), y2, x2, y2);
    }
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// 기록 확인 화면
class HistoryScreen extends StatelessWidget {
  final List<String> history;
  const HistoryScreen({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("운동 기록 리스트"), backgroundColor: Colors.black),
      body: history.isEmpty 
        ? const Center(child: Text("저장된 기록이 없습니다."))
        : ListView.builder(
            itemCount: history.length,
            itemBuilder: (context, index) => ListTile(
              leading: const Icon(Icons.directions_bike, color: Colors.redAccent),
              title: Text(history[index]),
              border: const Border(bottom: BorderSide(color: Colors.white10)),
            ),
          ),
    );
  }
}
