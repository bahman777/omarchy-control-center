import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "../ui"
import "../Icons.js" as Icons

// Outputs, inputs and per-app volume, live from PipeWire. Headsets and
// Bluetooth speakers appear as soon as they connect.
CcPage {
  id: page

  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var nodeNames: nodes.map(function(n) { return n ? String(n.name || "") : "" })

  function hidden(n) {
    var name = String(n.name || "")
    return name.indexOf("omarchy_speaker_tuning") === 0
      || AudioNodes.isShellLevelMeter(name) || AudioNodes.platformHides(name, nodeNames)
  }
  function label(n) {
    return String(n.description || n.nickname || n.name || "Unknown")
  }
  function iconFor(n, input) {
    var s = (label(n) + " " + String(n.name || "")).toLowerCase()
    if (s.indexOf("bluez") >= 0 || s.indexOf("headset") >= 0) return Icons.headset
    if (s.indexOf("headphone") >= 0) return Icons.headphones
    if (s.indexOf("hdmi") >= 0 || s.indexOf("displayport") >= 0) return Icons.monitor
    return input ? Icons.microphone : Icons.speaker
  }

  readonly property var sinks: nodes.filter(function(n) { return n && n.isSink && !n.isStream && n.audio && !page.hidden(n) })
  readonly property var sources: nodes.filter(function(n) {
    return n && !n.isSink && !n.isStream && n.audio && !page.hidden(n) && String(n.name || "").indexOf(".monitor") < 0
  })
  readonly property var streams: nodes.filter(function(n) { return n && n.isStream && n.isSink && n.audio && !page.hidden(n) })
  readonly property var recorders: nodes.filter(function(n) { return n && n.isStream && !n.isSink && n.audio && !page.hidden(n) })

  readonly property var defaultSink: Pipewire.defaultAudioSink
  readonly property var defaultSource: Pipewire.defaultAudioSource

  // Speaker tuning puts a filter in front of the hardware sink; volume belongs
  // on the sink omarchy-audio-output-sink names.
  property string volumeSinkName: ""
  readonly property var volumeSink: {
    for (var i = 0; i < sinks.length; i++) if (sinks[i].name === volumeSinkName) return sinks[i]
    return defaultSink
  }
  onDefaultSinkChanged: resolveSink.restart()
  Timer { id: resolveSink; interval: 150; triggeredOnStart: true; running: true
    onTriggered: page.cc.runner.run(["omarchy-audio-output-sink"], function(code, out) { page.volumeSinkName = String(out).trim() }) }

  PwObjectTracker { objects: page.sinks.concat(page.sources).concat(page.streams).concat(page.recorders) }

  function pct(v) { return Math.round(v * 100) + "%" }

  function setOutput(n) {
    cc.runner.run(["omarchy-audio-output-set-default", String(n.id), String(n.name)], null)
  }
  function setInput(n) {
    cc.runner.run(["omarchy-audio-input-set-default", String(n.id), String(n.name)], null)
  }

  // ------------------------------------------------------------ output
  CcGroup {
    title: "Output"
    CcSliderRow {
      icon: page.volumeSink && page.volumeSink.audio && page.volumeSink.audio.muted ? Icons.volumeOff : Icons.volume
      title: "Volume"
      subtitle: page.defaultSink ? page.label(page.defaultSink) : "No output device"
      from: 0; to: 1.5; stepSize: 0.01
      value: page.volumeSink && page.volumeSink.audio ? page.volumeSink.audio.volume : 0
      valueText: page.pct(value)
      onMoved: function(v) { if (page.volumeSink && page.volumeSink.audio) page.volumeSink.audio.volume = v }
      onCommitted: function(v) { if (page.volumeSink && page.volumeSink.audio) page.volumeSink.audio.volume = v }
    }
    CcSwitchRow {
      title: "Mute"
      checked: !!(page.volumeSink && page.volumeSink.audio && page.volumeSink.audio.muted)
      onToggled: if (page.volumeSink && page.volumeSink.audio) page.volumeSink.audio.muted = !page.volumeSink.audio.muted
    }
  }

  CcGroup {
    title: "Output devices"
    subtitle: "Headsets and Bluetooth speakers appear here when connected"
    Repeater {
      model: page.sinks
      delegate: CcRow {
        required property var modelData
        readonly property bool isDefault: page.defaultSink && (page.defaultSink.id === modelData.id || page.volumeSinkName === modelData.name)
        icon: page.iconFor(modelData, false)
        iconColor: isDefault ? page.cc.accent : page.cc.fg
        title: page.label(modelData)
        subtitle: isDefault ? "Active" : "Click to use"
        selected: isDefault
        clickable: !isDefault
        onClicked: page.setOutput(modelData)
        CcText { visible: parent && isDefault; text: Icons.check; color: page.cc.accent; font.family: Style.font.family; font.pixelSize: Style.font.icon }
      }
    }
  }

  // ------------------------------------------------------------ input
  CcGroup {
    title: "Input"
    visible: page.sources.length > 0
    CcSliderRow {
      icon: page.defaultSource && page.defaultSource.audio && page.defaultSource.audio.muted ? Icons.microphoneOff : Icons.microphone
      title: "Microphone volume"
      subtitle: page.defaultSource ? page.label(page.defaultSource) : "No input device"
      from: 0; to: 1; stepSize: 0.01
      value: page.defaultSource && page.defaultSource.audio ? page.defaultSource.audio.volume : 0
      valueText: page.pct(value)
      onMoved: function(v) { if (page.defaultSource && page.defaultSource.audio) page.defaultSource.audio.volume = v }
      onCommitted: function(v) { if (page.defaultSource && page.defaultSource.audio) page.defaultSource.audio.volume = v }
    }
    CcSwitchRow {
      title: "Mute microphone"
      subtitle: page.recorders.length > 0 ? "In use by " + page.recorders.map(function(n) { return String((n.properties || {})["application.name"] || n.name) }).join(", ") : ""
      checked: !!(page.defaultSource && page.defaultSource.audio && page.defaultSource.audio.muted)
      onToggled: page.cc.runner.run(["omarchy-audio-input-mute"], null)
    }
    Repeater {
      model: page.sources
      delegate: CcRow {
        required property var modelData
        readonly property bool isDefault: page.defaultSource && page.defaultSource.id === modelData.id
        icon: page.iconFor(modelData, true)
        iconColor: isDefault ? page.cc.accent : page.cc.fg
        title: page.label(modelData)
        subtitle: isDefault ? "Active" : "Click to use"
        selected: isDefault
        clickable: !isDefault
        onClicked: page.setInput(modelData)
      }
    }
  }

  // ------------------------------------------------------------ apps
  CcGroup {
    title: "Apps"
    subtitle: page.streams.length === 0 ? "Nothing is playing" : ""
    Repeater {
      model: page.streams
      delegate: CcSliderRow {
        required property var modelData
        readonly property var props: modelData.properties || {}
        icon: Icons.app
        title: String(props["application.name"] || page.label(modelData))
        subtitle: String(props["media.name"] || "")
        from: 0; to: 1.5; stepSize: 0.01
        value: modelData.audio ? modelData.audio.volume : 0
        valueText: modelData.audio && modelData.audio.muted ? "muted" : page.pct(value)
        onMoved: function(v) { if (modelData.audio) modelData.audio.volume = v }
        onCommitted: function(v) { if (modelData.audio) modelData.audio.volume = v }
        onRightClicked: if (modelData.audio) modelData.audio.muted = !modelData.audio.muted
        clickable: false
      }
    }
  }

  CcGroup {
    title: "Troubleshooting"
    CcRow {
      icon: Icons.refresh
      title: "Restart audio"
      subtitle: "Restart PipeWire and recover stuck USB audio devices"
      clickable: true
      onClicked: {
        page.cc.toast("Restarting audio…")
        page.cc.runner.run(["omarchy-restart-audio"], function(code) { page.cc.toast(code === 0 ? "Audio restarted" : "Audio restart failed") })
      }
    }
  }
}
