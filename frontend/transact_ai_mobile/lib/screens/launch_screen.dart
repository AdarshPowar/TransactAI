
import 'package:flutter/material.dart';
import '../theme/constants.dart';

class LaunchScreen extends StatefulWidget {
  final VoidCallback onGetStarted;

  const LaunchScreen({
    super.key,
    required this.onGetStarted,
  });

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen> with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _loadingController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _progressAnimation;
  late Animation<double> _fadeButtonAnimation;

  @override
  void initState() {
    super.initState();

    // Logo pulsing animation
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );

    // Simulated boot-up progress bar loading
    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _loadingController, curve: Curves.easeOutCubic),
    );

    // Fade-in the "Get Started" button when loading completes
    _fadeButtonAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _loadingController,
        // Start fading in during the last 20% of the progress
        curve: const Interval(0.8, 1.0, curve: Curves.easeIn),
      ),
    );

    _loadingController.forward();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _loadingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),

            // Animated Pulsing Geometric Logo
            ScaleTransition(
              scale: _pulseAnimation,
              child: SizedBox(
                width: 120,
                height: 120,
                child: CustomPaint(
                  painter: GeometricLogoPainter(),
                ),
              ),
            ),
            const SizedBox(height: 40),

            // Title & Subtitle
            Text(
              'TRANSACT AI',
              style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4.0,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'COGNITIVE TRANSACTION PIPELINE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 48),

            // Feature List Block
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border, width: 0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                children: [
                  _FeatureRow(title: 'Deterministic Heuristic Rules', detail: 'Instant matching'),
                  SizedBox(height: 12),
                  _FeatureRow(title: 'DistilBERT Sequence Model', detail: 'ML classification'),
                  SizedBox(height: 12),
                  _FeatureRow(title: 'SentenceTransformer Fallback', detail: 'Semantic resolver'),
                ],
              ),
            ),

            const Spacer(),

            // Progress Loader / Get Started CTA
            AnimatedBuilder(
              animation: _loadingController,
              builder: (context, child) {
                final isDone = _loadingController.isCompleted || _progressAnimation.value > 0.99;
                
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isDone) ...[
                      // Progress Bar
                      Stack(
                        children: [
                          Container(
                            width: double.infinity,
                            height: 2,
                            color: AppColors.border,
                          ),
                          FractionallySizedBox(
                            widthFactor: _progressAnimation.value,
                            child: Container(
                              height: 2,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'BOOTING PIPELINE MOTORS...',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            '${(_progressAnimation.value * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // Get Started Button
                      FadeTransition(
                        opacity: _fadeButtonAnimation,
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: widget.onGetStarted,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Get Started',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(Icons.arrow_forward, size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String title;
  final String detail;

  const _FeatureRow({
    super.key,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Text(
          detail,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class GeometricLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Draw concentric circles
    canvas.drawCircle(center, size.width / 4, paint);

    // Draw diamond outline
    final path = Path();
    path.moveTo(center.dx, 0); // top
    path.lineTo(size.width, center.dy); // right
    path.lineTo(center.dx, size.height); // bottom
    path.lineTo(0, center.dy); // left
    path.close();
    canvas.drawPath(path, paint);

    // Draw tech crossbars
    paint.color = Colors.white.withValues(alpha: 0.3);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paint);
    
    // Draw 4 accent vertex circles
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
      
    canvas.drawCircle(Offset(center.dx, 0), 3.0, dotPaint);
    canvas.drawCircle(Offset(size.width, center.dy), 3.0, dotPaint);
    canvas.drawCircle(Offset(center.dx, size.height), 3.0, dotPaint);
    canvas.drawCircle(Offset(0, center.dy), 3.0, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
