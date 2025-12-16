// lib/pages/home.dart - FINAL FIXED CODE
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tour/pages/add_post_page.dart';
import 'package:tour/pages/login_screen.dart';
import 'package:tour/pages/profile_page.dart';
import 'package:tour/pages/register_screen.dart';
import 'package:tour/widgets/travel_post_widget.dart';

// Assuming UserProfilePage is a valid widget, used in navigation
// import 'package:tour/pages/user_profile_page.dart'; 


class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final ScrollController _scrollController = ScrollController();
  int _selectedIndex = 0;
  bool _showUserDropdown = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _searchController = TextEditingController();
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    // Listen to auth state changes
    _auth.authStateChanges().listen((User? user) {
      if (mounted) {
        setState(() {
          _currentUser = user;
        });
      }
    });
    
    // Get initial user
    _currentUser = _auth.currentUser;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await _auth.signOut();
      setState(() {
        _showUserDropdown = false;
      });
    } catch (e) {
      print('Logout error: $e');
    }
  }

  void _searchDestinations() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      print('Searching for: $query');
      // TODO: Implement search functionality
    }
  }

  // Show login prompt when guest tries protected action
  void _showLoginPrompt(BuildContext context, {String action = ''}) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline,
                size: 32,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              action.isNotEmpty ? '$action requires login' : 'Sign in required',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Create an account to share your travel stories, like posts, and connect with other travelers.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/login');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Sign In',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/register');
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: const BorderSide(color: Colors.deepPurple),
                ),
                child: const Text(
                  'Create Account',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.deepPurple,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                'Continue as Guest',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        // Stack layers the fixed user button/dropdown OVER the scrolling content
        child: Stack(
          children: [
            // 1. The main scrolling view (Hero content + Posts list)
            _buildContentScroll(),
            
            // 2. Fixed Overlays (User Button and Dropdown)
            _buildUserProfileButton(_currentUser),
            if (_showUserDropdown) _buildUserDropdown(context),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  // Contains the visual elements of the Hero section (no scroll logic)
  Widget _buildHeroContent() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: const AssetImage('images/home.jpg'), // Ensure asset path is correct
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          colorFilter: ColorFilter.mode(
            Colors.black.withAlpha(77),
            BlendMode.darken,
          ),
        ),
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withAlpha(204),
              Colors.transparent,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 60.0, left: 20.0, right: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Voyage',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 70,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'DancingScript',
                  shadows: [
                    Shadow(
                      blurRadius: 15,
                      color: Colors.black,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Share your travel adventures with the world',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w300,
                  shadows: [
                    Shadow(
                      blurRadius: 8,
                      color: Colors.black,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              // Search Bar
              Container(
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(51),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: Colors.white.withAlpha(102)
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(77),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Search your destination...',
                            hintStyle: TextStyle(
                              color: Colors.white.withAlpha(204)
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            fillColor: Colors.transparent,
                          ),
                          onSubmitted: (_) => _searchDestinations(),
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          onPressed: () {
                            _searchController.clear();
                            _searchDestinations();
                          },
                          icon: const Icon(Icons.close, color: Colors.white, size: 18),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // FIX: Consolidated Hero and List into a single CustomScrollView
  Widget _buildContentScroll() {
   final double heroHeight = MediaQuery.of(context).size.height * 0.55;

  return CustomScrollView(
    controller: _scrollController,
    physics: const BouncingScrollPhysics(),
    slivers: [

      // 🔥 HERO SECTION
      SliverAppBar(
        expandedHeight: heroHeight,
        backgroundColor: Colors.black,
        automaticallyImplyLeading: false,
        pinned: false,
        flexibleSpace: FlexibleSpaceBar(
          background: _buildHeroContent(),
        ),
      ),

      // 🔥 POSTS LIST
      StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {

          if (!snapshot.hasData) {
            return const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
           if (snapshot.hasError) {
              return SliverToBoxAdapter(
                  child: Center(
                      child: Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text('Firestore error: ${snapshot.error}'),
              )));
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const SliverToBoxAdapter(
                  child: Center(
                      child: Padding(
                padding: EdgeInsets.only(top: 20, bottom: 80),
                child: Text('No travel posts found. Start sharing!'),
              )));
            }

            // The main list of posts using SliverList
            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final doc = snapshot.data!.docs[index];
                  final post = doc.data() as Map<String, dynamic>;

                  return TravelPostWidget(
  post: post,
  postId: doc.id,
  onLikeChanged: () {
    final user = _auth.currentUser;
    if (user == null) {
      _showLoginPrompt(context, action: 'Liking posts');
      return;
    }
    // TODO: Implement like functionality
  },
  onCommentPressed: () {
    final user = _auth.currentUser;
    if (user == null) {
      _showLoginPrompt(context, action: 'Commenting');
      return;
    }
    // TODO: Implement comment functionality
  },
);
                },
                childCount: snapshot.data!.docs.length,
              ),
            );
          },
        ),

        // 3. Spacing for the Bottom Navigation Bar
        const SliverToBoxAdapter(
          child: SizedBox(height: 70),
        )
      ],
    );
  }

  Widget _buildUserProfileButton(User? user) {
    if (user == null) {
      return Positioned(
        top: 10,
        right: 16,
        child: Row(
          children: [
            const SizedBox(width: 8),
            // Sign In button
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/login');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                elevation: 3,
              ),
              child: const Text(
                'Sign In',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Logged-in user - show profile picture
    return Positioned(
      top: 10,
      right: 16,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showUserDropdown = !_showUserDropdown;
          });
        },
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(102),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipOval(
            child: user.photoURL != null
                ? Image.network(
                    user.photoURL!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Image.asset(
                        'images/boy.jpg', // Ensure asset path is correct
                        fit: BoxFit.cover,
                      );
                    },
                  )
                : Image.asset(
                    'images/boy.jpg', // Ensure asset path is correct
                    fit: BoxFit.cover,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserDropdown(BuildContext context) {
    final currentUser = _auth.currentUser;

    return GestureDetector(
      onTap: () {
        setState(() => _showUserDropdown = false);
      },
      child: Stack(
        children: [
          // This transparent container makes the tap detection work for closing the dropdown
          Positioned.fill(child: Container(color: Colors.transparent)),
          Positioned(
            top: 65,
            right: 16,
            child: GestureDetector(
              onTap: () {}, // Prevent taps on the dropdown itself from closing the menu
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 220,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(38),
                        blurRadius: 15,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple[50],
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundImage: currentUser!.photoURL != null
                                  ? NetworkImage(currentUser.photoURL!)
                                  : const AssetImage('images/boy.jpg') as ImageProvider, // Ensure asset path is correct
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentUser.displayName ?? 'Traveler',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    currentUser.email ?? 'user@example.com',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              // Ensure UserProfilePage is imported/accessible
                              MaterialPageRoute(builder: (context) => const UserProfilePage()), 
                            );
                            setState(() => _showUserDropdown = false);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            child: const Row(
                              children: [
                                Icon(Icons.person, color: Colors.deepPurple, size: 22),
                                SizedBox(width: 12),
                                Text(
                                  'My Profile',
                                  style: TextStyle(
                                    color: Colors.deepPurple,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            setState(() => _showUserDropdown = false);
                            _logout(context);
                          },
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            child: const Row(
                              children: [
                                Icon(Icons.logout, color: Colors.red, size: 22),
                                SizedBox(width: 12),
                                Text(
                                  'Log Out',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.grey.withAlpha(51),
            width: 1,
          ),
        ),
      ),
      child: BottomAppBar(
        color: Colors.white,
        height: 65,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavBarItem(
              icon: Icons.home,
              label: 'Home',
              isSelected: _selectedIndex == 0,
              onTap: () => _onItemTapped(0),
            ),
            Container(
              width: 75,
              height: 75,
              margin: const EdgeInsets.only(bottom: 15),
              child: FloatingActionButton(
                onPressed: () {
                  final user = _auth.currentUser;
                  if (user == null) {
                    _showLoginPrompt(context, action: 'Creating a post');
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AddPostPage()),
                  );
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
                  child: const Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
            _buildNavBarItem(
              icon: Icons.person,
              label: 'Profile',
              isSelected: _selectedIndex == 1,
              onTap: () {
                final user = _auth.currentUser;
                if (user == null) {
                  _showLoginPrompt(context, action: 'Viewing profile');
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => UserProfilePage()),
                );
                setState(() => _selectedIndex = 1);
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
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }
}