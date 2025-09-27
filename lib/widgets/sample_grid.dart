import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:live_audio_sampler/providers/audio_provider.dart';
import 'package:live_audio_sampler/providers/sample_provider.dart';
import 'package:live_audio_sampler/widgets/sample_button.dart';
import 'package:live_audio_sampler/widgets/add_sample_button.dart';
import 'package:file_picker/file_picker.dart';

class SampleGrid extends StatelessWidget {
  const SampleGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SampleProvider>(
      builder: (context, sampleProvider, child) {
        final samples = sampleProvider.currentPageSamples;
        final totalSlots = sampleProvider.samplesPerPage;
        
        return Container(
          padding: const EdgeInsets.all(16),
          child: MasonryGridView.count(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            itemCount: totalSlots,
            itemBuilder: (context, index) {
              if (index < samples.length) {
                return SampleButton(sample: samples[index]);
              } else {
                return AddSampleButton(
                  onTap: () => _showAddSampleDialog(context),
                );
              }
            },
          ),
        );
      },
    );
  }

  void _showAddSampleDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const AddSampleDialog(),
    );
  }
}

class AddSampleDialog extends StatefulWidget {
  const AddSampleDialog({super.key});

  @override
  State<AddSampleDialog> createState() => _AddSampleDialogState();
}

class _AddSampleDialogState extends State<AddSampleDialog> {
  final _nameController = TextEditingController();
  String _selectedCategory = 'General';
  final _notesController = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Sample'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Sample Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Consumer<SampleProvider>(
            builder: (context, sampleProvider, child) {
              return DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: sampleProvider.categories
                    .where((cat) => cat != 'All')
                    .map((category) {
                  return DropdownMenuItem(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedCategory = value;
                    });
                  }
                },
              );
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _pickAudioFile,
            icon: _isLoading 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.audio_file),
            label: Text(_isLoading ? 'Loading...' : 'Select Audio File'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Future<void> _pickAudioFile() async {
    setState(() { _isLoading = true; });
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);
    final sampleProvider = Provider.of<SampleProvider>(context, listen: false);

    // Use file_picker to pick audio file
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac'],
    );
    if (result == null || result.files.isEmpty) {
      setState(() { _isLoading = false; });
      return;
    }
    final filePath = result.files.single.path;
    if (filePath == null) {
      setState(() { _isLoading = false; });
      return;
    }

    final duration = await audioProvider.getAudioDuration(filePath);
    // Add shell immediately so it appears in the grid
    final shell = await sampleProvider.addSampleShell(
      name: _nameController.text.isEmpty ? 'New Sample' : _nameController.text,
      category: _selectedCategory,
      filePath: filePath,
      duration: duration,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    );
  setState(() { _isLoading = false; });
  if (!mounted) return;
  Navigator.of(context).pop();
    // Generate waveform asynchronously and update
    final waveformData = await audioProvider.generateWaveformData(filePath);
    if (waveformData != null) {
      await sampleProvider.setSampleWaveform(shell.id, waveformData);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}