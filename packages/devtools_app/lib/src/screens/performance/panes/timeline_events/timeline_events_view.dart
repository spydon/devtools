// Copyright 2023 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:devtools_app_shared/ui.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:flutter/material.dart';

import '../../../../shared/analytics/constants.dart' as gac;
import '../../../../shared/common_widgets.dart';
import '../../../../shared/globals.dart';
import '../../../../shared/http/http_service.dart' as http_service;
import 'perfetto/perfetto.dart';
import 'timeline_events_controller.dart';

class TimelineEventsTabView extends StatelessWidget {
  const TimelineEventsTabView({super.key, required this.controller});

  final TimelineEventsController controller;

  @override
  Widget build(BuildContext context) {
    return KeepAliveWrapper(
      child: EmbeddedPerfetto(
        perfettoController: controller.perfettoController,
      ),
    );
  }
}

class TimelineEventsTabControls extends StatelessWidget {
  const TimelineEventsTabControls({super.key, required this.controller});

  final TimelineEventsController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: densePadding),
          child: PerfettoHelpButton(
            perfettoController: controller.perfettoController,
          ),
        ),
        if (!offlineController.offlineMode.value) ...[
          // TODO(kenz): add a switch to enable the CPU profiler once the
          // tracing format supports it (when we switch to protozero).
          const SizedBox(width: densePadding),
          TimelineSettingsButton(controller: controller),
          const SizedBox(width: densePadding),
          RefreshTimelineEventsButton(controller: controller),
        ],
      ],
    );
  }
}

class TimelineSettingsButton extends StatelessWidget {
  const TimelineSettingsButton({required this.controller, super.key});

  final TimelineEventsController controller;

  @override
  Widget build(BuildContext context) {
    return GaDevToolsButton.iconOnly(
      icon: Icons.settings_outlined,
      outlined: false,
      tooltip: 'Timeline settings',
      gaScreen: gac.performance,
      gaSelection: gac.PerformanceEvents.timelineSettings.name,
      onPressed: () => _openTimelineSettingsDialog(context),
    );
  }

  void _openTimelineSettingsDialog(BuildContext context) {
    unawaited(
      showDialog(
        context: context,
        builder: (context) => const TimelineSettingsDialog(),
      ),
    );
  }
}

class RefreshTimelineEventsButton extends StatelessWidget {
  const RefreshTimelineEventsButton({required this.controller, super.key});

  final TimelineEventsController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EventsControllerStatus>(
      valueListenable: controller.status,
      builder: (context, status, _) {
        return RefreshButton(
          iconOnly: true,
          outlined: false,
          onPressed: status == EventsControllerStatus.processing
              ? null
              : controller.forceRefresh,
          tooltip: 'Refresh timeline events',
          gaScreen: gac.performance,
          gaSelection: gac.PerformanceEvents.refreshTimelineEvents.name,
        );
      },
    );
  }
}

class TimelineSettingsDialog extends StatefulWidget {
  const TimelineSettingsDialog({super.key});

  @override
  State<TimelineSettingsDialog> createState() => _TimelineSettingsDialogState();
}

class _TimelineSettingsDialogState extends State<TimelineSettingsDialog>
    with AutoDisposeMixin {
  late final ValueNotifier<bool?> _httpLogging;

  @override
  void initState() {
    super.initState();
    // Mirror the value of [http_service.httpLoggingState] in the [_httpLogging]
    // notifier so that we can use [_httpLogging] for the [CheckboxSetting]
    // widget below.
    _httpLogging = ValueNotifier<bool>(http_service.httpLoggingEnabled);
    addAutoDisposeListener(http_service.httpLoggingState, () {
      _httpLogging.value = http_service.httpLoggingState.value.enabled;
    });
  }

  @override
  void dispose() {
    cancelListeners();
    _httpLogging.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DevToolsDialog(
      title: const DialogTitleText('Timeline Settings'),
      includeDivider: false,
      content: SizedBox(
        width: defaultDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._defaultRecordedStreams(theme),
            const SizedBox(height: denseSpacing),
            ..._advancedStreams(theme),
          ],
        ),
      ),
      actions: const [
        DialogCloseButton(),
      ],
    );
  }

  List<Widget> _defaultRecordedStreams(ThemeData theme) {
    return [
      ...dialogSubHeader(theme, 'General'),
      CheckboxSetting(
        notifier: preferences.performance.includeCpuSamplesInTimeline,
        title: 'Include CPU samples in the timeline',
        description: 'This may negatively affect performance.',
      ),
      const SizedBox(height: defaultSpacing),
      ...dialogSubHeader(theme, 'Trace categories'),
      RichText(
        text: TextSpan(
          text: 'Default',
          style: theme.subtleTextStyle,
        ),
      ),
      ..._timelineStreams(advanced: false),
      // Special case "Network Traffic" because it is not implemented as a
      // Timeline recorded stream in the VM. The user does not need to be aware of
      // the distinction, however.
      CheckboxSetting(
        title: 'Network',
        description: 'Http traffic',
        notifier: _httpLogging,
        onChanged: (value) => unawaited(
          http_service.toggleHttpRequestLogging(value ?? false),
        ),
      ),
    ];
  }

  List<Widget> _advancedStreams(ThemeData theme) {
    return [
      RichText(
        text: TextSpan(
          text: 'Advanced',
          style: theme.subtleTextStyle,
        ),
      ),
      ..._timelineStreams(advanced: true),
    ];
  }

  List<Widget> _timelineStreams({
    required bool advanced,
  }) {
    final streams = advanced
        ? serviceConnection.timelineStreamManager.advancedStreams
        : serviceConnection.timelineStreamManager.basicStreams;
    final settings = streams
        .map(
          (stream) => CheckboxSetting(
            title: stream.name,
            description: stream.description,
            notifier: stream.recorded as ValueNotifier<bool?>,
            onChanged: (newValue) => unawaited(
              serviceConnection.timelineStreamManager.updateTimelineStream(
                stream,
                newValue ?? false,
              ),
            ),
          ),
        )
        .toList();
    return settings;
  }
}
