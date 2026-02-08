import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/library.dart';
import '../services/cover_service.dart';
import '../services/library_store.dart';
import 'reader_screen.dart';

class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({super.key});

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen>
    with WidgetsBindingObserver {
  final _store = LibraryStore.instance;
  String? _selectedFolderId;
  bool _loading = true;
  bool _selectionMode = false;
  final Set<String> _selectedBookIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _store.init();
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshInbox();
    }
  }

  Future<void> _refreshInbox() async {
    final imported = await _store.refreshInbox();
    if (imported.isNotEmpty && mounted) {
      setState(() {});
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['epub', 'pdf', 'txt', 'md', 'markdown'],
    );
    if (result == null) return;
    final files = result.paths.whereType<String>().toList();
    if (files.isEmpty) return;
    await _store.importFiles(files, folderId: _selectedFolderId);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _store.createFolder(name);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _moveSelectedBooks() async {
    if (_selectedBookIds.isEmpty) return;
    final folderId = await showModalBottomSheet<String?>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('移出文件夹'),
                onTap: () => Navigator.pop(context, null),
              ),
              for (final folder in _store.state.folders)
                ListTile(
                  title: Text(folder.name),
                  onTap: () => Navigator.pop(context, folder.id),
                ),
            ],
          ),
        );
      },
    );
    for (final bookId in _selectedBookIds) {
      await _store.moveBook(bookId, folderId);
    }
    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedBookIds.clear();
    });
  }

  Future<void> _deleteSelectedBooks() async {
    if (_selectedBookIds.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除书籍'),
        content: Text('确定要删除已选的 ${_selectedBookIds.length} 本书吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final bookId in _selectedBookIds) {
      await _store.deleteBook(bookId);
    }
    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedBookIds.clear();
    });
  }

  void _enterSelection(Book book) {
    setState(() {
      _selectionMode = true;
      _selectedBookIds.add(book.id);
    });
  }

  void _toggleSelection(Book book) {
    setState(() {
      if (_selectedBookIds.contains(book.id)) {
        _selectedBookIds.remove(book.id);
      } else {
        _selectedBookIds.add(book.id);
      }
      if (_selectedBookIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectedBookIds.clear();
    });
  }

  void _selectAll(List<Book> books) {
    if (books.isEmpty) return;
    setState(() {
      _selectionMode = true;
      if (_selectedBookIds.length == books.length) {
        _selectedBookIds.clear();
        _selectionMode = false;
      } else {
        _selectedBookIds
          ..clear()
          ..addAll(books.map((book) => book.id));
      }
    });
  }

  Future<void> _deleteFolder(Folder folder) async {
    final count = _store.state.books
        .where((book) => book.folderId == folder.id)
        .length;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('仅删除文件夹（移出 $count 本图书）'),
              onTap: () => Navigator.pop(context, 'keep'),
            ),
            ListTile(
              title: Text('删除文件夹并移除 $count 本图书'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            ListTile(
              title: const Text('取消'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'keep') {
      await _store.deleteFolder(folder.id);
    } else if (choice == 'delete') {
      await _store.deleteFolderAndBooks(folder.id);
      if (_selectedFolderId == folder.id) {
        _selectedFolderId = null;
      }
    }
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final folders = _store.state.folders;
    final books = _store.state.books
        .where((book) => _selectedFolderId == null
            ? book.folderId == null
            : book.folderId == _selectedFolderId)
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));

    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('已选 ${_selectedBookIds.length} 本')
            : Text(_selectedFolderId == null
                ? '书架'
                : folders
                    .firstWhere((folder) => folder.id == _selectedFolderId)
                    .name),
        leading: _selectionMode
            ? IconButton(
                onPressed: _clearSelection,
                icon: const Icon(Icons.close),
                tooltip: '取消选择',
              )
            : _selectedFolderId == null
                ? null
                : IconButton(
                    onPressed: () =>
                        setState(() => _selectedFolderId = null),
                    icon: const Icon(Icons.arrow_back),
                  ),
        actions: [
          if (_selectionMode) ...[
            IconButton(
              onPressed: _selectedBookIds.isEmpty ? null : _moveSelectedBooks,
              icon: const Icon(Icons.drive_file_move_outlined),
              tooltip: '移动',
            ),
            IconButton(
              onPressed:
                  _selectedBookIds.isEmpty ? null : _deleteSelectedBooks,
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
            ),
            IconButton(
              onPressed: books.isEmpty ? null : () => _selectAll(books),
              icon: Icon(
                _selectedBookIds.length == books.length && books.isNotEmpty
                    ? Icons.remove_done
                    : Icons.select_all,
              ),
              tooltip: _selectedBookIds.length == books.length &&
                      books.isNotEmpty
                  ? '取消全选'
                  : '全选',
            ),
          ] else ...[
            IconButton(
              onPressed: _createFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: '新建文件夹',
            ),
            IconButton(
              onPressed: _pickFiles,
              icon: const Icon(Icons.add),
              tooltip: '导入',
            ),
          ],
        ],
      ),
      body: books.isEmpty && _selectedFolderId != null
          ? _EmptyState(onImport: _pickFiles)
          : CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                if (_selectedFolderId == null && folders.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.72,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final folder = folders[index];
                          final folderBooks = _store.state.books
                              .where((book) => book.folderId == folder.id)
                              .toList()
                            ..sort(
                                (a, b) => b.addedAt.compareTo(a.addedAt));
                          return _FolderTile(
                            folder: folder,
                            books: folderBooks.take(4).toList(),
                            onTap: () =>
                                setState(() => _selectedFolderId = folder.id),
                            onLongPress: () => _deleteFolder(folder),
                          );
                        },
                        childCount: folders.length,
                      ),
                    ),
                  ),
                if (_selectedFolderId == null && folders.isNotEmpty)
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                if (books.isEmpty && _selectedFolderId == null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(onImport: _pickFiles),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.72,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final book = books[index];
                          final selected =
                              _selectedBookIds.contains(book.id);
                          return _BookTile(
                            book: book,
                            selectionMode: _selectionMode,
                            selected: selected,
                            onOpen: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ReaderScreen(book: book),
                                ),
                              );
                            },
                            onEnterSelection: () => _enterSelection(book),
                            onToggleSelection: () => _toggleSelection(book),
                          );
                        },
                        childCount: books.length,
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_outlined, size: 56),
            const SizedBox(height: 12),
            const Text(
              '书架里还没有书籍',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add),
              label: const Text('导入书籍'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.book,
    required this.selectionMode,
    required this.selected,
    required this.onOpen,
    required this.onEnterSelection,
    required this.onToggleSelection,
  });

  final Book book;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onEnterSelection;
  final VoidCallback onToggleSelection;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: selectionMode ? onToggleSelection : onOpen,
      onLongPress: selectionMode ? onToggleSelection : onEnterSelection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _BookCover(book: book)),
                if (selectionMode)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      decoration: BoxDecoration(
                        color:
                            selected ? Colors.black87 : Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        selected ? Icons.check : Icons.circle_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final service = CoverService.instance;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: const Color(0xFFF2F2F2),
        child: FutureBuilder<Uint8List?>(
          future: service.loadCover(book),
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes != null && bytes.isNotEmpty) {
              return Image.memory(
                bytes,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (context, error, stackTrace) =>
                    _buildPlaceholder(),
              );
            }
            return _buildPlaceholder();
          },
        ),
      ),
    );
  }

  String _fallbackCoverText(Book book) {
    final filename = p.basenameWithoutExtension(book.path);
    if (filename.isEmpty) return book.title;
    final cleaned = filename.replaceFirst(RegExp(r'^\d+_'), '');
    return cleaned.isEmpty ? book.title : cleaned;
  }

  Widget _buildPlaceholder() {
    return Container(
      color: CoverService.placeholderColor(book.title),
      padding: const EdgeInsets.all(12),
      alignment: Alignment.center,
      child: Text(
        _fallbackCoverText(book),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.books,
    required this.onTap,
    required this.onLongPress,
  });

  final Folder folder;
  final List<Book> books;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                color: const Color(0xFFEFEFEF),
                padding: const EdgeInsets.all(6),
                child: _FolderCoverGrid(books: books),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _FolderCoverGrid extends StatelessWidget {
  const _FolderCoverGrid({required this.books});

  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return const Center(child: Icon(Icons.folder, size: 36));
    }
    final tiles = books
        .take(4)
        .map((book) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: _FolderCoverTile(book: book),
            ))
        .toList();
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      children: tiles,
    );
  }
}

class _FolderCoverTile extends StatelessWidget {
  const _FolderCoverTile({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    return _BookCover(book: book);
  }
}
