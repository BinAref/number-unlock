import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_services.dart';
import '../../services/pwa/pwa_install.dart';
import '../../ui/kit/glyphs.dart';
import '../../ui/kit/widgets.dart';
import '../common/page_frame.dart';
import '../home/home_screen.dart';

/// The player's profile card: emblem, name and journey records.
void showProfile(BuildContext context) => SettingsScreen._card(context);

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final i18n = s.i18n;
    final p = s.player;
    return PageFrame(
      title: i18n.t('settings.title'),
      child: ListenableBuilder(
        listenable: p,
        builder: (context, _) => StonePanel(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(children: [
            _Row(Glyph.music, i18n.t('settings.music'), StoneToggle(value: p.settings.music, onChanged: (v) {
              p.updateSettings((x) => x.music = v);
              s.audio.setMusic(v);
            })),
            _Row(Glyph.sound, i18n.t('settings.sfx'), StoneToggle(value: p.settings.sfx, onChanged: (v) {
              p.updateSettings((x) => x.sfx = v);
              s.audio.setSfx(v);
            })),
            _Row(Glyph.vibrate, i18n.t('settings.vibration'), StoneToggle(value: p.settings.vibration, onChanged: (v) {
              p.updateSettings((x) => x.vibration = v);
              s.haptics.enabled = v;
            })),
            _Row(Glyph.sparkle, i18n.t('settings.reduceEffects'), StoneToggle(value: p.settings.reducedEffects, onChanged: (v) => p.updateSettings((x) => x.reducedEffects = v))),
            const SizedBox(height: 6),
            _Row(Glyph.globe, i18n.t('settings.language'), Wrap(spacing: 6, children: [
              for (final l in i18n.languages)
                _Chip(label: l.name, selected: l.code == i18n.current.code, onTap: () {
                  p.updateSettings((x) => x.language = l.code);
                  i18n.setLanguage(l.code);
                }),
            ])),
            _Row(Glyph.theme, i18n.t('settings.theme'), Wrap(spacing: 6, children: [
              for (final id in ['system', ...s.theme.themes.map((t) => t.id)])
                _Chip(
                  label: i18n.t(id == 'system' ? 'theme.system' : s.theme.themes.firstWhere((t) => t.id == id).nameKey),
                  selected: s.theme.selection == id,
                  onTap: () {
                    p.updateSettings((x) => x.theme = id);
                    s.theme.select(id);
                  },
                ),
            ])),
            const SizedBox(height: 8),
            _Link(Glyph.user, i18n.t('settings.profile'), () => _profile(context)),
            _Link(Glyph.help, i18n.t('settings.support'), () => _info(context, 'support.title', 'support.body', s.config.supportUrl, 'support.open')),
            _Link(Glyph.info, i18n.t('settings.about'), () => _about(context)),
            _Link(Glyph.shield, i18n.t('settings.privacy'), () => _info(context, 'privacy.title', 'privacy.body', s.config.privacyUrl, 'privacy.open')),
            if (PwaInstall.available) _Link(Glyph.download, i18n.t('settings.install'), () => _install(context)),
          ]),
        ),
      ),
    );
  }

  static void _card(BuildContext context) {
    final s = Services.of(context, listen: false);
    final i18n = s.i18n;
    final p = s.player;
    final t = s.theme.tokens;
    Widget stat(Glyph g, String key, int value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            GlyphIcon(g, size: 18, color: t.color('gold.light')),
            const SizedBox(width: 10),
            Expanded(child: Text(i18n.t(key), style: UiText.style(context, size: 15))),
            Text('$value', style: UiText.numbers(context, size: 16, color: t.color('text.accent'))),
          ]),
        );
    showStoneDialog<void>(context, title: p.profile.name ?? i18n.t('profile.defaultName'), builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
          stat(Glyph.lock, 'profile.stage', p.progress.highestUnlocked),
          stat(Glyph.sparkle, 'profile.stars', p.progress.totalStars),
          stat(Glyph.plus, 'profile.coins', p.coins),
          stat(Glyph.trophy, 'profile.best', p.bestScore),
          stat(Glyph.hint, 'profile.bestTier', p.bestTier),
          stat(Glyph.check, 'profile.solved', p.challengesSolved),
          const SizedBox(height: 14),
          StoneButton(label: i18n.t('profile.edit'), glyph: Glyph.user, onTap: () {
            Navigator.pop(context);
            _profile(context);
          }),
        ]));
  }

  static Future<void> _open(String url) async {
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  static void _info(BuildContext context, String title, String body, String url, String action) {
    final i18n = Services.of(context, listen: false).i18n;
    showStoneDialog<void>(context, title: i18n.t(title), builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
          Text(i18n.t(body), textAlign: TextAlign.center, style: UiText.style(context, size: 15)),
          const SizedBox(height: 16),
          StoneButton(label: i18n.t(action), primary: true, onTap: () => _open(url)),
          const SizedBox(height: 8),
          StoneButton(label: i18n.t('common.close'), dense: true, onTap: () => Navigator.pop(context)),
        ]));
  }

  static void _about(BuildContext context) {
    final s = Services.of(context, listen: false);
    final i18n = s.i18n;
    showStoneDialog<void>(context, title: i18n.t('about.title'), builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
          Text(i18n.t('about.body'), textAlign: TextAlign.center, style: UiText.style(context, size: 15)),
          const SizedBox(height: 10),
          Text(i18n.t('about.version', {'v': s.config.version}), style: UiText.style(context, size: 13, color: s.theme.tokens.color('text.muted'))),
          Text(i18n.t('about.credits'), style: UiText.style(context, size: 13, color: s.theme.tokens.color('text.muted'))),
          const SizedBox(height: 14),
          StoneButton(label: i18n.t('about.licenses'), dense: true, onTap: () => showLicensePage(context: context, applicationName: i18n.t('app.name'), applicationVersion: s.config.version)),
          const SizedBox(height: 8),
          StoneButton(label: i18n.t('common.close'), dense: true, onTap: () => Navigator.pop(context)),
        ]));
  }

  static Future<void> _install(BuildContext context) async {
    final i18n = Services.of(context, listen: false).i18n;
    if (PwaInstall.canPrompt) {
      final ok = await PwaInstall.prompt();
      if (ok && context.mounted) showToast(context, i18n.t('install.done'), glyph: Glyph.check);
      return;
    }
    if (!context.mounted) return;
    showStoneDialog<void>(context, title: i18n.t('install.title'), builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
          Text(i18n.t('install.body'), textAlign: TextAlign.center, style: UiText.style(context, size: 15)),
          const SizedBox(height: 10),
          Text(i18n.t('install.manual'), textAlign: TextAlign.center, style: UiText.style(context, size: 14)),
          const SizedBox(height: 14),
          StoneButton(label: i18n.t('common.ok'), primary: true, onTap: () => Navigator.pop(context)),
        ]));
  }

  static void _profile(BuildContext context) {
    final s = Services.of(context, listen: false);
    final i18n = s.i18n;
    final controller = TextEditingController(text: s.player.profile.name ?? '');
    var avatar = s.player.profile.avatar;
    showStoneDialog<void>(context, title: i18n.t('profile.title'), builder: (context) => StatefulBuilder(builder: (context, set) {
          final t = s.theme.tokens;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: controller,
              maxLength: 18,
              textAlign: TextAlign.center,
              style: UiText.style(context, size: 18),
              cursorColor: t.color('text.accent'),
              decoration: InputDecoration(
                hintText: i18n.t('profile.nameHint'),
                hintStyle: UiText.style(context, size: 16, color: t.color('text.muted'), shadow: false),
                counterStyle: UiText.style(context, size: 11, color: t.color('text.muted'), shadow: false),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: t.color('gold.base'))),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: t.color('text.accent'), width: 2)),
              ),
            ),
            const SizedBox(height: 8),
            Text(i18n.t('profile.emblem'), style: UiText.style(context, size: 14, color: t.color('text.muted'))),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
              for (var i = 0; i < kEmblems.length; i++)
                Pressable(
                  onTap: () => set(() => avatar = i),
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: t.color(i == avatar ? 'stone.purple' : 'ui.panelDeep'), border: Border.all(color: t.color(i == avatar ? 'text.accent' : 'gold.dark'), width: 2.5)),
                    child: Center(child: GlyphIcon(kEmblems[i], size: 22, color: t.color('gold.light'))),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            StoneButton(label: i18n.t('profile.save'), primary: true, onTap: () {
              s.player.updateProfile(name: controller.text, avatar: avatar);
              Navigator.pop(context);
            }),
          ]);
        }));
  }
}

class _Row extends StatelessWidget {
  const _Row(this.glyph, this.label, this.control);

  final Glyph glyph;
  final String label;
  final Widget control;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          GlyphIcon(glyph, size: 22, color: Services.of(context).theme.tokens.color('gold.light')),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: UiText.style(context, size: 16))),
          Flexible(child: Align(alignment: AlignmentDirectional.centerEnd, child: control)),
        ]),
      );
}

class _Link extends StatelessWidget {
  const _Link(this.glyph, this.label, this.onTap);

  final Glyph glyph;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rtl = Services.of(context).i18n.current.rtl;
    return Pressable(onTap: onTap, semantics: label, child: _Row(glyph, label, GlyphIcon(rtl ? Glyph.arrowLeft : Glyph.arrowRight, size: 18)));
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Services.of(context).theme.tokens;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: t.color(selected ? 'stone.purple' : 'ui.panelDeep'),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.color(selected ? 'text.accent' : 'gold.dark'), width: 2),
        ),
        child: Text(label, style: UiText.style(context, size: 13)),
      ),
    );
  }
}
