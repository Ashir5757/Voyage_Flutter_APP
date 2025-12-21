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
  // 0 = My Posts, 1 = Profile, 2 = Add Post (FAB)
  int? _loadingNavIndex;

  Future<void> _handleNavigation(int index, BuildContext context, VoidCallback navigationAction) async {
    if (_loadingNavIndex != null) return;

    setState(() => _loadingNavIndex = index);

    // 1. Stop Music
    Provider.of<AudioService>(context, listen: false).stop();

    // 2. Small delay for responsiveness
    await Future.delayed(const Duration(milliseconds: 150));

    // 3. Execute Navigation
    navigationAction();

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
          // Moving SafeArea to wrap both content and the navigation bar
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
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
                // Custom Bottom Nav Bar moved inside the Column and SafeArea
                _buildBottomNavBar(controller, context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomNavBar(HomeController controller, BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.withAlpha(51), width: 1),
        ),
      ),
      child: BottomAppBar(
        color: Colors.white,
        // Removed fixed height to let SafeArea handle padding dynamically
        padding: const EdgeInsets.symmetric(horizontal: 10),
        elevation: 0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavBarItem(
              icon: Icons.grid_view_rounded,
              label: 'My Posts',
              isSelected: false,
              isLoading: _loadingNavIndex == 0,
              onTap: () {
                _handleNavigation(0, context, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const MyPostsPage()),
                  );
                });
              },
            ),
            
            // --- ADD POST FAB ---
            SizedBox(
              width: 70,
              height: 70,
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
                backgroundColor: Colors.transparent,
                elevation: 0,
                child: Container(
                  width: 60,
                  height: 60,
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
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: _loadingNavIndex == 2
                      ? const Padding(
                          padding: EdgeInsets.all(18.0),
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.add, color: Colors.white, size: 28),
                ),
              ),
            ),

            _buildNavBarItem(
              icon: Icons.person,
              label: 'Profile',
              isSelected: controller.selectedIndex == 1,
              isLoading: _loadingNavIndex == 1,
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
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.deepPurple,
                ),
              )
            else
              Icon(
                icon,
                size: 26,
                color: isSelected ? Colors.deepPurple : Colors.grey[600],
              ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
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