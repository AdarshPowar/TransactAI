import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/constants.dart';

class DonutChartData {
  final String label;
  final double amount;
  final Color color;

  DonutChartData({
    required this.label,
    required this.amount,
    required this.color,
  });
}

class DonutChart extends StatefulWidget {
  final List<DonutChartData> data;
  final double totalAmount;

  const DonutChart({
    super.key,
    required this.data,
    required this.totalAmount,
  });

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.fastOutSlowIn,
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant DonutChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.reset();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(200, 200),
                painter: DonutChartPainter(
                  data: widget.data,
                  totalAmount: widget.totalAmount,
                  animationProgress: _animation.value,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'TOTAL EXPENSE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${widget.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class DonutChartPainter extends CustomPainter {
  final List<DonutChartData> data;
  final double totalAmount;
  final double animationProgress;

  DonutChartPainter({
    required this.data,
    required this.totalAmount,
    required this.animationProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2) - 15.0;
    
    const strokeWidth = 14.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    paint.color = AppColors.border;
    canvas.drawCircle(center, radius, paint);

    if (totalAmount <= 0) return;

    double startAngle = -pi / 2;

    for (var segment in data) {
      final percentage = segment.amount / totalAmount;
      final sweepAngle = percentage * 2 * pi * animationProgress;

      if (sweepAngle > 0.01) {
        paint.color = segment.color;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          sweepAngle,
          false,
          paint,
        );
      }
      
      startAngle += percentage * 2 * pi;
    }
  }

  @override
  bool shouldRepaint(covariant DonutChartPainter oldDelegate) {
    return oldDelegate.animationProgress != animationProgress ||
        oldDelegate.data != data ||
        oldDelegate.totalAmount != totalAmount;
  }
}
