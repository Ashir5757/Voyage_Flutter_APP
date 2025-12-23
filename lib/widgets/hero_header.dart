import 'package:flutter/material.dart';

class HeroHeader extends StatelessWidget {
  const HeroHeader({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. We remove the fixed height (SizedBox).
    // 2. We use StackFit.expand so it fills the FlexibleSpaceBar area completely.
    return Stack(
      fit: StackFit.expand, 
      children: [
        // Background Gradient
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
            ),
          ),
        ),
        
        // Decorative Circles (Background elements)
        Positioned(
          top: -100, right: -100,
          child: Container(
            width: 300, height: 300,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.05)),
          ),
        ),
        Positioned(
          top: 100, left: -50,
          child: Container(
            width: 200, height: 200,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.03)),
          ),
        ),
        Positioned(
          bottom: -50, right: -20,
          child: Container(
            width: 150, height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Colors.tealAccent.withOpacity(0.2), Colors.transparent],
              ),
            ),
          ),
        ),
        
        // Text Content - Aligned to bottom-left so it stays visible longer
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 60, left: 24, right: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min, // Important: Wraps content height
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.travel_explore, color: Colors.tealAccent, size: 40),
                const SizedBox(height: 16),
                const Text(
                  'Voyage',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 60,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'DancingScript',
                    shadows: [Shadow(blurRadius: 10.0, color: Colors.black45, offset: Offset(2.0, 2.0))],
                  ),
                ),
                const Text(
                  'Explore the world with us',
                  style: TextStyle(color: Colors.white70, fontSize: 16, letterSpacing: 1.2),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}