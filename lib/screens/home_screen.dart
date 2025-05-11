// // lib/screens/home_screen.dart
// import 'package:flutter/material.dart';
// import 'group_list_screen.dart';

// // class HomeScreen extends StatefulWidget {
// //   const HomeScreen({Key? key}) : super(key: key);

// //   @override
// //   _HomeScreenState createState() => _HomeScreenState();
// // }

// // class _HomeScreenState extends State<HomeScreen> {
// //   int _selectedIndex = 0;

// //   final List<Widget> _screens = [
// //     ChatScreen(), // Existing chat view
// //     FilesScreen(), // New file listing view
// //   ];

// //   void _onItemTapped(int index) {
// //     setState(() {
// //       _selectedIndex = index;
// //     });
// //   }

// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       body: _screens[_selectedIndex],
// //       bottomNavigationBar: BottomNavigationBar(
// //         currentIndex: _selectedIndex,
// //         onTap: _onItemTapped,
// //         items: const [
// //           BottomNavigationBarItem(
// //             icon: Icon(Icons.chat),
// //             label: 'Chat',
// //           ),
// //           BottomNavigationBarItem(
// //             icon: Icon(Icons.folder),
// //             label: 'Files',
// //           ),
// //         ],
// //         // Optional: Customize colors to match your theme
// //         backgroundColor: Colors.black,
// //         selectedItemColor: const Color(0xFFEF8275),
// //         unselectedItemColor: Colors.white,
// //       ),
// //     );
// //   }
// // }
// // Redirect to the new group picker screen
// class HomeScreen extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return GroupListScreen();
//   }
// }
