// DiskSpace GUI App (JXA)
// Lightweight macOS app that wraps the diskspace CLI
// Build: osacompile -l JavaScript -o ~/Applications/DiskSpace.app ~/DiskSpaceApp.js

'use strict';
ObjC.import('stdlib');

function quoted(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

function humanKB(kb) {
  var k = Number(kb) || 0;
  if (k >= 1048576) return (k/1048576).toFixed(1) + ' GB';
  if (k >= 1024) return (k/1024).toFixed(1) + ' MB';
  return k + ' KB';
}

function run(argv) {
  var app = Application.currentApplication();
  app.includeStandardAdditions = true;
  var home = $.getenv('HOME').toString();

  function findDiskspace() {
    var candidates = ['/usr/local/bin/diskspace', home + '/diskspace'];
    for (var i = 0; i < candidates.length; i++) {
      try { app.doShellScript('test -x ' + quoted(candidates[i])); return candidates[i]; } catch (e) {}
    }
    return null;
  }

  var ds = findDiskspace();
  if (!ds) {
    app.displayDialog('Cannot find diskspace binary. Please install to /usr/local/bin or ~/diskspace.', {withTitle: 'DiskSpace', buttons: ['OK'], defaultButton: 'OK'});
    return;
  }

  function doCheck() {
    var json = app.doShellScript(quoted(ds) + ' check --json');
    var data = JSON.parse(json);
    var msg = 'Usage: ' + data.disk_usage_percent + '%\nFree: ' + data.free_space + '\n';
    var problems = (data.cleanup_opportunities && data.cleanup_opportunities.problems) || [];
    if (problems.length) {
      msg += '\nTop opportunities:\n';
      var lim = Math.min(problems.length, 8);
      for (var i=0;i<lim;i++) {
        var p = problems[i];
        msg += '• ' + p.description + ' — ' + humanKB(p.size) + '\n';
      }
    } else {
      msg += '\nNo significant cleanup opportunities.';
    }
    return {data: data, message: msg};
  }

  function doAutoClean() {
    try { app.doShellScript(quoted(ds) + ' auto-clean'); app.displayNotification('Auto-clean completed', {withTitle: 'DiskSpace'}); }
    catch (e) { app.displayDialog('Auto-clean failed:\n' + e.toString(), {withTitle: 'DiskSpace', buttons: ['OK'], defaultButton: 'OK'}); }
  }

  function doInteractiveClean() {
    var Terminal = Application('Terminal');
    Terminal.activate();
    Terminal.doScript(quoted(ds) + ' clean');
  }

  function doSchedule() {
    try { app.doShellScript(quoted(ds) + ' schedule'); app.displayNotification('Scheduled daily check at 10:00 AM', {withTitle: 'DiskSpace'}); }
    catch (e) { app.displayDialog('Scheduling failed:\n' + e.toString(), {withTitle: 'DiskSpace', buttons: ['OK'], defaultButton: 'OK'}); }
  }

  function doUnschedule() {
    try { app.doShellScript(quoted(ds) + ' unschedule'); app.displayNotification('Schedule removed', {withTitle: 'DiskSpace'}); }
    catch (e) { app.displayDialog('Unschedule failed:\n' + e.toString(), {withTitle: 'DiskSpace', buttons: ['OK'], defaultButton: 'OK'}); }
  }

  var result = doCheck();
  var choice = app.displayDialog(result.message, {
    withTitle: 'DiskSpace',
    buttons: ['Auto Clean', 'More…', 'Quit'],
    defaultButton: 'Auto Clean',
    cancelButton: 'Quit'
  });
  var btn = choice.buttonReturned;
  if (btn === 'Auto Clean') {
    doAutoClean();
  } else if (btn === 'More…') {
    var options = ['Interactive Clean', 'Schedule Daily', 'Unschedule', 'Open Report in Terminal'];
    var picked = app.chooseFromList(options, {
      withTitle: 'DiskSpace: Actions',
      withPrompt: 'Choose an action',
      multipleSelectionsAllowed: false
    });
    if (!picked) return; // user cancelled
    switch (picked[0]) {
      case 'Interactive Clean':
        doInteractiveClean();
        break;
      case 'Schedule Daily':
        doSchedule();
        break;
      case 'Unschedule':
        doUnschedule();
        break;
      case 'Open Report in Terminal':
        var Terminal = Application('Terminal');
        Terminal.activate();
        Terminal.doScript(quoted(ds) + ' check');
        break;
    }
  }
}
