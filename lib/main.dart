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
  int bpm = 104;
  int targetMinutes = 21;
  int elapsedSeconds = 0;
  bool isRunning = false;
  List<double> heartPoints = List.generate(40, (index) => 20.0);
  List<String> workoutHistory = []; 
  Timer? dataTimer;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    dataTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (mounted) {
        setState(() {
          bpm = 100 + Random().nextInt(10);
          heartPoints.add(Random().nextDouble() * 40 + 10);
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
    String record = "${DateTime.now().hour}:${DateTime.now().minute} | ${elapsedSeconds ~/ 60}분 ${elapsedSeconds % 60}초 완료";
    setState(() => workoutHistory.add(record));
    Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryScreen(history: workoutHistory)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage("assets/background.png"), fit: BoxFit.cover),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 30),
              const Text("Over the Bike Fit", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w200, letterSpacing: 2)),
              
              // [개선] 배경과 그라데이션으로 합성되는 그래프 배너
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(25),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.black.withOpacity(0.8),
                      Colors.red.withOpacity(0.1), // 배경과 섞이는 붉은 기운
                      Colors.black.withOpacity(0.8),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.red.withOpacity(0.1), blurRadius: 20, spreadRadius: 5)
                  ],
                ),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.favorite, color: Colors.redAccent, size: 22),
                      const SizedBox(width: 12),
                      Text("$bpm bpm", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: -1)),
                    ]),
                    const SizedBox(height: 20),
                    // [개선] 더 고급스러운 커스텀 그래프
                    SizedBox(
                      height: 80, 
                      width: double.infinity, 
                      child: CustomPaint(painter: PremiumWavePainter(heartPoints))
                    ),
                  ],
                ),
              ),

              const Spacer(),
              
              // 하단 컨트롤 패널 (반투명 블랙)
              Container(
                padding: const EdgeInsets.fromLTRB(30, 40, 30, 40),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85), 
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(40))
                ),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      statWidget("운동시간", "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.redAccent),
                      Container(width: 1, height: 30, color: Colors.white10),
                      targetWidget(),
                    ]),
                    const SizedBox(height: 35),
                    Row(children: [
                      btn(isRunning ? "정지" : "시작", isRunning ? Colors.orange : Colors.redAccent.withOpacity(0.8), toggleWorkout),
                      const SizedBox(width: 15),
                      btn("리셋", Colors.white10, () => setState(() => elapsedSeconds = 0)),
                      const SizedBox(width: 15),
                      btn("저장", Colors.green.withOpacity(0.7), saveRecord),
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

  Widget statWidget(String t, String v, Color c) => Column(children: [Text(t, style: const TextStyle(color: Colors.grey, fontSize: 13)), const SizedBox(height: 5), Text(v, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c))]);

  Widget targetWidget() => Column(children: [
    const Text("목표시간", style: TextStyle(color: Colors.grey, fontSize: 13)),
    Row(children: [
      IconButton(icon: const Icon(Icons.remove, size: 20), onPressed: () => setState(() => targetMinutes--)),
      Text("$targetMinutes분", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      IconButton(icon: const Icon(Icons.add, size: 20), onPressed: () => setState(() => targetMinutes++)),
    ])
  ]);

  Widget btn(String t, Color c, VoidCallback f) => Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: c, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), onPressed: f, child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold))));
}

// [개선] 프리미엄 곡선 Painter (그라데이션 채우기 효과)
class PremiumWavePainter extends CustomPainter {
  final List<double> points;
  PremiumWavePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final fillPath = Path(); // 하단 채우기용 패스
    final xStep = size.width / (points.length - 1);
    
    path.moveTo(0, size.height - points[0]);
    fillPath.moveTo(0, size.height);
    fillPath.lineTo(0, size.height - points[0]);

    for (int i = 0; i < points.length - 1; i++) {
      var x1 = i * xStep;
      var y1 = size.height - points[i];
      var x2 = (i + 1) * xStep;
      var y2 = size.height - points[i + 1];
      path.cubicTo(x1 + (xStep / 2), y1, x1 + (xStep / 2), y2, x2, y2);
      fillPath.cubicTo(x1 + (xStep / 2), y1, x1 + (xStep / 2), y2, x2, y2);
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // 1. 선 아래 은은한 그라데이션 채우기
    final fillPaint = Paint()..shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.redAccent.withOpacity(0.2), Colors.transparent],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // 2. 메인 네온 라인
    final linePaint = Paint()..color = Colors.redAccent..strokeWidth = 3.0..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class HistoryScreen extends StatelessWidget {
  final List<String> history;
  const HistoryScreen({super.key, required this.history});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("운동 기록"), backgroundColor: Colors.black, elevation: 0),
      body: ListView.builder(
        itemCount: history.length,
        itemBuilder: (context, i) => ListTile(title: Text(history[i]), leading: const Icon(Icons.history, color: Colors.redAccent)),
      ),
    );
  }
}
