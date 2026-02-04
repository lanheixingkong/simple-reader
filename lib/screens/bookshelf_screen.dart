import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/library.dart';
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

  Future<void> _moveBook(Book book) async {
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
    await _store.moveBook(book.id, folderId);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _deleteBook(Book book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除书籍'),
        content: Text('确定要删除《${book.title}》吗？'),
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
    await _store.deleteBook(book.id);
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
            ? true
            : book.folderId == _selectedFolderId)
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));

    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        actions: [
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
      ),
      body: Column(
        children: [
          _FolderChips(
            folders: folders,
            selectedFolderId: _selectedFolderId,
            onSelected: (id) => setState(() => _selectedFolderId = id),
          ),
          Expanded(
            child: books.isEmpty
                ? _EmptyState(onImport: _pickFiles)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemBuilder: (context, index) {
                      final book = books[index];
                      return ListTile(
                        title: Text(book.title),
                        subtitle: Text(book.format.extensionLabel.toUpperCase()),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'move') {
                              _moveBook(book);
                            } else if (value == 'delete') {
                              _deleteBook(book);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'move',
                              child: Text('移动到文件夹'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('删除'),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ReaderScreen(book: book),
                            ),
                          );
                        },
                      );
                    },
                    separatorBuilder: (_, index) =>
                        const Divider(height: 1),
                    itemCount: books.length,
                  ),
          ),
        ],
      ),
    );
  }
}

class _FolderChips extends StatelessWidget {
  const _FolderChips({
    required this.folders,
    required this.selectedFolderId,
    required this.onSelected,
  });

  final List<Folder> folders;
  final String? selectedFolderId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          ChoiceChip(
            label: const Text('全部'),
            selected: selectedFolderId == null,
            onSelected: (_) => onSelected(null),
          ),
          const SizedBox(width: 8),
          for (final folder in folders) ...[
            ChoiceChip(
              label: Text(folder.name),
              selected: selectedFolderId == folder.id,
              onSelected: (_) => onSelected(folder.id),
            ),
            const SizedBox(width: 8),
          ],
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
