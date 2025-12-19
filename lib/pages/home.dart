import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tour/controllers/home_controller.dart';
import 'package:tour/services/audio_service.dart';
import 'package:tour/widgets/home_content.dart';
import 'package:tour/pages/my_posts_page.dart'; 

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  // Track which navigation item is currently loading
  // 0 = My Posts, 1 = Profile, 2 = Add Post (FAB)
  int? _loadingNavIndex;

  // Helper to handle navigation with visual feedback
  Future<void> _handleNavigation(int index, BuildContext context, VoidCallback navigationAction) async {
    if (_loadingNavIndex != null) return; // Prevent double clicks

    setState(() => _loadingNavIndex = index);

    // 1. Stop Music
    Provider.of<AudioService>(context, listen: false).stop();

    // 2. Small delay to ensure the loader is seen and UI feels responsive
    await Future.delayed(const Duration(milliseconds: 150));

    // 3. Execute Navigation
    navigationAction();

    // 4. Reset loader after navigation is pushed
    // (We use mounted check to be safe)
    if (mounted) {
      setState(() => _loadingNavIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeController>(
      builder: (context, controller, child) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: HomeContent(
              controller: controller,
              searchController: controller.searchController,
              selectedIndex: controller.selectedIndex,
              showUserDropdown: controller.showUserDropdown,
              onSearchSubmitted: () => controller.searchDestinations(),
              onNavItemTapped: controller.onItemTapped,
              
              onUserProfileTap: () {
                Provider.of<AudioService>(context, listen: false).stop();
                controller.toggleUserDropdown();
              },
              
              onCloseDropdown: () => controller.closeUserDropdown(),
              
              onLoginTap: () {
                Provider.of<AudioService>(context, listen: false).stop();
                controller.navigateToLogin(context);
              },
              
              onProfileTap: () {
                Provider.of<AudioService>(context, listen: false).stop();
                controller.navigateToProfile(context);
              },
              
              onLogoutTap: () {
                Provider.of<AudioService>(context, listen: false).stop();
                controller.logout(context);
              },
              
              onCreatePostTap: () => controller.navigateToCreatePost(context),
            ),
          ),
          bottomNavigationBar: _buildBottomNavBar(controller, context),
        );
      },
    );
  }

  Widget _buildBottomNavBar(HomeController controller, BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.withAlpha(51), width: 1),
        ),
      ),
      child: BottomAppBar(
        color: Colors.white,
        height: 65,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // --- 1. MY POSTS BUTTON ---
            _buildNavBarItem(
              icon: Icons.grid_view_rounded, 
              label: 'My Posts',
              isSelected: false,
              isLoading: _loadingNavIndex == 0, // Check if this specific button is loading
              onTap: () {
                _handleNavigation(0, context, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const MyPostsPage()),
                  );
                });
              },
            ),
            
            // --- 2. ADD POST FAB ---
            Container(
              width: 75,
              height: 75,
              margin: const EdgeInsets.only(bottom: 15),
              child: FloatingActionButton(
                onPressed: () {
                  _handleNavigation(2, context, () {
                    if (controller.currentUser == null) {
                      controller.showLoginPrompt(context, action: 'Creating a post');
                    } else {
                      controller.navigateToCreatePost(context);
                    }
                  });
                },
                backgroundColor: Colors.white,
                elevation: 0,
                child: Container(
                  width: 75,
                  height: 75,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.deepPurple, Colors.purpleAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepPurple.withAlpha(77),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: _loadingNavIndex == 2
                      ? const Padding(
                          padding: EdgeInsets.all(22.0),
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                        )
                      : const Icon(Icons.add, color: Colors.white, size: 32),
                ),
              ),
            ),
            
            // --- 3. PROFILE BUTTON ---
            _buildNavBarItem(
              icon: Icons.person,
              label: 'Profile',
              isSelected: controller.selectedIndex == 1,
              isLoading: _loadingNavIndex == 1, // Check if this specific button is loading
              onTap: () {
                _handleNavigation(1, context, () {
                  controller.navigateToProfile(context);
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavBarItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required bool isLoading, // Added this parameter
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: isLoading ? null : onTap, // Disable tap if already loading
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Swap Icon for Loader if loading
            if (isLoading)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.deepPurple,
                ),
              )
            else
              Icon(
                icon,
                size: 28,
                color: isSelected ? Colors.deepPurple : Colors.grey[600],
              ),
              
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? Colors.deepPurple : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}