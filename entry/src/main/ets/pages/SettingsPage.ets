import { Tokens } from '../theme/Tokens';
import { ThemePref, ThemeStore } from '../store/ThemeStore';
import { PrefStore } from '../store/PrefStore';
import { ReadPrefStore } from '../store/ReadPrefStore';
import { Haptics } from '../utils/Haptics';
import { motionMs, pressMs } from '../utils/Motion';
import { BreakpointStore } from '../store/BreakpointStore';
import { common } from '@kit.AbilityKit';
import { HuAvatar, HuAvatarPicker } from '../components/HuAvatar';
import { materializeForCrop, pickOneImageUri, resolveAvatarPhoto, toFileUri } from '../utils/ImagePicker';
import { AvatarCrop } from '../components/AvatarCrop';
import { HuButton } from '../components/HuButton';
import { HuTextButton } from '../components/HuTextButton';
import { HuIconButton } from '../components/HuIconButton';
import { HuSwitch } from '../components/HuSwitch';
import { normalizeAvatarId } from '../utils/AvatarPresets';
import { SessionVM } from '../viewmodels/SessionVM';
import { confirmDanger } from '../utils/AppDialog';
import { notifyResult, showToast } from '../utils/AppToast';
import { readClipboardText } from '../utils/Clipboard';
import { pushInAppBrowser, WebLinks } from '../utils/WebLinks';

@Builder
export function SettingsPageBuilder() {
  SettingsPage()
}

@Component
struct SettingsPage {
  @Consume('navPathStack') navStack: NavPathStack;
  private session: SessionVM = SessionVM.getInstance();
  @State inputKey: string = '';
  @State hasKey: boolean = false;
  @State email: string = '';
  @State keyName: string = '';
  @State userName: string = '';
  @State maskedKey: string = '';
  @State busy: boolean = false;
  @State errorMsg: string = '';
  @State themePref: string = 'system';
  @State defaultAutoPR: boolean = false;
  @State hapticsEnabled: boolean = true;
  @State soundsEnabled: boolean = true;
  @State notifyEnabled: boolean = true;
  @State diagEnabled: boolean = true;
  @State defaultModel: string = '';
  @State appVersion: string = '1.0.0';
  @State topInset: number = 0;
  @State bottomInset: number = 0;
  @State showReplace: boolean = false;
  @State typePref: string = 'default';
  @State densityCompact: boolean = false;
  @State pressKey: string = '';
  @State avatarPreset: string = 'iridescent';
  @State avatarPhoto: string = '';
  @State showAvatarEdit: boolean = false;
  @State cropUri: string = '';

  aboutToAppear(): void {
    const bp = BreakpointStore.getInstance();
    this.topInset = bp.safeTop();
    this.bottomInset = bp.composerBottom();
    bp.onChange(() => {
      this.topInset = bp.safeTop();
      this.bottomInset = bp.composerBottom();
    });
    this.pull();
    this.themePref = ThemeStore.getInstance().pref;
    this.loadPrefs();
    this.appVersion = '1.0.0';
  }

  private async loadPrefs(): Promise<void> {
    const prefs = PrefStore.getInstance();
    this.defaultAutoPR = await prefs.getDefaultAutoPR();
    this.hapticsEnabled = await prefs.getHapticsEnabled();
    this.soundsEnabled = await prefs.getSoundsEnabled();
    this.notifyEnabled = await prefs.getNotifyEnabled();
    this.diagEnabled = await prefs.getDiagEnabled();
    this.defaultModel = await prefs.getDefaultModel();
    const preset = normalizeAvatarId(await prefs.getAvatarPreset());
    const photo = await resolveAvatarPhoto(await prefs.getAvatarPhoto());
    if (preset === 'custom' && photo.length === 0) {
      this.avatarPreset = 'iridescent';
      this.avatarPhoto = '';
      prefs.setAvatarPreset('iridescent');
      prefs.setAvatarPhoto('');
    } else {
      this.avatarPreset = preset;
      this.avatarPhoto = preset === 'custom' ? photo : '';
    }
    const read = ReadPrefStore.getInstance();
    this.typePref = read.typePref;
    this.densityCompact = read.densityPref === 'compact';
  }

  private pull(): void {
    this.session.syncFromStore();
    this.hasKey = this.session.hasKey;
    this.email = this.session.email;
    this.keyName = this.session.keyName;
    this.userName = this.session.userName;
    this.maskedKey = this.session.maskedKey;
    this.busy = this.session.busy;
    this.errorMsg = this.session.errorMsg;
  }

  private modelLine(): string {
    if (this.defaultModel.length === 0) {
      return '自动';
    }
    const s = this.defaultModel.replace(/^Cursor\s+/i, '').replace(/-/g, ' ');
    if (s.length === 0) {
      return this.defaultModel;
    }
    return s.charAt(0).toUpperCase() + s.substring(1);
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          HuIconButton({
            name: 'back',
            label: '返回',
            onTap: () => {
              this.session.notifyUi();
              this.navStack.pop();
            }
          })
          Text('设置')
            .fontSize(Tokens.typeHeadline)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .height(Tokens.touchMin)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({
          left: Tokens.chromePad,
          right: Tokens.chromePad,
          top: this.topInset + 2,
          bottom: 6
        })

        Scroll() {
          Column({ space: Tokens.sec }) {
            this.sectionLabel('账号')
            Column() {
              Row({ space: 12 }) {
                HuAvatar({
                  preset: this.avatarPreset,
                  photoUri: this.avatarPreset === 'custom' ? this.avatarPhoto : '',
                  box: Tokens.touchMin,
                  onTap: () => {
                    this.showAvatarEdit = !this.showAvatarEdit;
                  }
                })
                Text(this.showAvatarEdit ? '从相册选一张' : '点头像更换')
                  .fontSize(Tokens.typeCaption)
                  .fontColor($r('app.color.text_tertiary'))
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ top: 12, bottom: 8 })
              .alignItems(VerticalAlign.Center)
              if (this.cropUri.length > 0) {
                AvatarCrop({
                  src: this.cropUri,
                  onCancel: () => {
                    this.cropUri = '';
                  },
                  onDone: async (path: string) => {
                    this.avatarPhoto = toFileUri(path);
                    this.avatarPreset = 'custom';
                    this.cropUri = '';
                    await PrefStore.getInstance().setAvatarPreset('custom');
                    await PrefStore.getInstance().setAvatarPhoto(toFileUri(path));
                  }
                })
              } else if (this.showAvatarEdit) {
                HuAvatarPicker({
                  selected: this.avatarPreset,
                  photoUri: this.avatarPreset === 'custom' ? this.avatarPhoto : '',
                  onPick: async (id: string) => {
                    this.avatarPreset = normalizeAvatarId(id);
                    await PrefStore.getInstance().setAvatarPreset(this.avatarPreset);
                  },
                  onPhoto: async () => {
                    const uri = await pickOneImageUri();
                    if (uri.length === 0) {
                      return;
                    }
                    const ctx = getContext(this) as common.UIAbilityContext;
                    const local = await materializeForCrop(uri, ctx.cacheDir);
                    if (local.length === 0) {
                      showToast('这张图读不了');
                      return;
                    }
                    this.cropUri = toFileUri(local);
                  }
                })
              }
              this.hair()
              if (this.hasKey) {
                if (this.userName.length > 0) {
                  this.infoRow('姓名', this.userName)
                }
                if (this.email.length > 0) {
                  this.infoRow('邮箱', this.email)
                }
                if (this.maskedKey.length > 0) {
                  this.infoRow('Key', this.keyName.length > 0 ?
                    `${this.maskedKey} · ${this.keyName}` : this.maskedKey)
                }
                this.hair()
                this.actionRow(this.showReplace ? '取消更换' : '更换 Key', $r('app.color.text_primary'),
                  false, () => {
                    this.showReplace = !this.showReplace;
                  })
                if (this.showReplace) {
                  this.keyPaste()
                }
                this.actionRow('重新验证', $r('app.color.text_primary'), this.busy, async () => {
                  this.busy = true;
                  const ok = await this.session.validateExisting();
                  this.pull();
                  notifyResult(ok, '验证通过', this.session.errorMsg.length > 0 ?
                    this.session.errorMsg : '验证失败');
                })
                this.actionRow('清除 Key', $r('app.color.err'), false, () => {
                  confirmDanger('清除 API Key', '清除后需要重新粘贴才能同步任务。', '清除', () => {
                    this.session.clearKey().then(() => {
                      this.inputKey = '';
                      this.pull();
                      showToast('已清除');
                    });
                  });
                })
              } else {
                this.keyGuide()
                this.keyPaste()
                this.privacyNote()
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
            .backgroundColor($r('app.color.bg1'))
            .borderRadius(Tokens.radiusCard)
            .border({ width: 1, color: $r('app.color.border') })
            .clip(true)

            this.sectionLabel('任务')
            Column() {
              HuSwitch({
                on: this.defaultAutoPR,
                label: '默认自动创建 PR',
                onToggle: async () => {
                  this.defaultAutoPR = !this.defaultAutoPR;
                  await PrefStore.getInstance().setDefaultAutoPR(this.defaultAutoPR);
                }
              })
              HuSwitch({
                on: this.hapticsEnabled,
                label: '触感反馈',
                onToggle: async () => {
                  this.hapticsEnabled = !this.hapticsEnabled;
                  await PrefStore.getInstance().setHapticsEnabled(this.hapticsEnabled);
                  if (this.hapticsEnabled) {
                    Haptics.toggle();
                  }
                }
              })
              HuSwitch({
                on: this.soundsEnabled,
                label: '音效反馈',
                onToggle: async () => {
                  this.soundsEnabled = !this.soundsEnabled;
                  await PrefStore.getInstance().setSoundsEnabled(this.soundsEnabled);
                  if (this.soundsEnabled) {
                    Haptics.toggle();
                  }
                }
              })
              this.hair()
              HuSwitch({
                on: this.notifyEnabled,
                label: '完成通知',
                hint: '后台用一条摘要，当前会话不弹',
                onToggle: async () => {
                  this.notifyEnabled = !this.notifyEnabled;
                  await PrefStore.getInstance().setNotifyEnabled(this.notifyEnabled);
                }
              })
              HuSwitch({
                on: this.diagEnabled,
                label: '诊断日志',
                hint: '写入本机文件，不含正文和密钥',
                onToggle: async () => {
                  this.diagEnabled = !this.diagEnabled;
                  await PrefStore.getInstance().setDiagEnabled(this.diagEnabled);
                }
              })
              this.hair()
              this.infoRow('默认模型', this.modelLine())
              if (this.defaultModel.length > 0) {
                this.actionRow('清除默认模型', $r('app.color.text_secondary'), false, async () => {
                  await PrefStore.getInstance().setDefaultModel('');
                  this.defaultModel = '';
                })
              }
            }
            .width('100%')
            .padding({ left: 16, right: 12, top: 4, bottom: 4 })
            .backgroundColor($r('app.color.bg1'))
            .borderRadius(Tokens.radiusCard)
            .border({ width: 1, color: $r('app.color.border') })

            this.sectionLabel('显示')
            Column({ space: 10 }) {
              Row() {
                Column() {
                  this.themeSeg('system', '跟随')
                }
                .layoutWeight(1)
                Column() {
                  this.themeSeg('light', '浅色')
                }
                .layoutWeight(1)
                Column() {
                  this.themeSeg('dark', '深色')
                }
                .layoutWeight(1)
              }
              .width('100%')
              .height(36)
              .padding(3)
              .backgroundColor($r('app.color.bg2'))
              .borderRadius(Tokens.radiusMd)
              Column({ space: 6 }) {
                Text('字号')
                  .fontSize(Tokens.typeCaption)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
                Row() {
                  Column() {
                    this.typeSeg('small', '偏小')
                  }
                  .layoutWeight(1)
                  Column() {
                    this.typeSeg('default', '默认')
                  }
                  .layoutWeight(1)
                  Column() {
                    this.typeSeg('large', '偏大')
                  }
                  .layoutWeight(1)
                }
                .width('100%')
                .height(36)
                .padding(3)
                .backgroundColor($r('app.color.bg2'))
                .borderRadius(Tokens.radiusMd)
              }
              .width('100%')
              HuSwitch({
                on: this.densityCompact,
                label: '紧凑',
                hint: '只收卡片和页边距',
                onToggle: async () => {
                  this.densityCompact = !this.densityCompact;
                  await ReadPrefStore.getInstance().setDensity(this.densityCompact ? 'compact' : 'comfortable');
                }
              })
            }
            .width('100%')
            .padding({ left: 16, right: 12, top: 12, bottom: 8 })
            .backgroundColor($r('app.color.bg1'))
            .borderRadius(Tokens.radiusCard)
            .border({ width: 1, color: $r('app.color.border') })

            this.sectionLabel('关于')
            Column() {
              this.infoRow('应用', 'Cursor Cloud Agents')
              this.infoRow('版本', this.appVersion)
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
            .backgroundColor($r('app.color.bg1'))
            .borderRadius(Tokens.radiusCard)
            .border({ width: 1, color: $r('app.color.border') })
            .clip(true)
          }
          .padding({
            left: Tokens.pagePad,
            right: Tokens.pagePad,
            bottom: this.bottomInset + 16
          })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg0'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg0'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }

  @Builder
  sectionLabel(title: string) {
    Text(title)
      .fontSize(Tokens.typeCaption)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .margin({ top: 4, left: 4 })
  }

  @Builder
  hair() {
    Divider()
      .color($r('app.color.separator'))
      .width('100%')
  }

  @Builder
  infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(Tokens.typeBody)
        .fontColor($r('app.color.text_primary'))
      Blank().layoutWeight(1)
      Text(value)
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '62%' })
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .height(48)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  actionRow(label: string, color: Resource, disabled: boolean, action: () => void) {
    Text(label)
      .fontSize(Tokens.typeBody)
      .fontColor(color)
      .width('100%')
      .height(48)
      .textAlign(TextAlign.Start)
      .opacity(disabled ? 0.4 : (this.pressKey === `act:${label}` ? 0.7 : 1))
      .animation({ duration: pressMs(), curve: Curve.EaseOut })
      .onTouch((e: TouchEvent) => {
        if (disabled) {
          return;
        }
        if (e.type === TouchType.Down) {
          this.pressKey = `act:${label}`;
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          this.pressKey = '';
        }
      })
      .onClick(() => {
        if (!disabled) {
          Haptics.click();
          action();
        }
      })
  }

  @Builder
  keyGuide() {
    Column({ space: 8 }) {
      Text('在 Cursor 网站创建 User API Key，复制以 crsr_ 开头的一串。')
        .fontSize(Tokens.typeCallout)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(Tokens.lineCaption)
        .width('100%')
      Row({ space: 16 }) {
        HuTextButton({
          label: '打开 API Keys',
          color: $r('app.color.text_link'),
          compact: true,
          external: true,
          onTap: () => {
            pushInAppBrowser(this.navStack, WebLinks.apiKeys, 'API Keys');
          }
        })
        HuTextButton({
          label: '官方说明',
          color: $r('app.color.text_link'),
          compact: true,
          external: true,
          onTap: () => {
            pushInAppBrowser(this.navStack, WebLinks.docsApiOverview, 'API 说明');
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ top: 12, bottom: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  privacyNote() {
    Text('本应用使用 Cursor 官方开放 API。所有信息都直达 Cursor 服务器，无需担心安全和隐私问题。')
      .fontSize(Tokens.typeMicro)
      .fontColor($r('app.color.text_tertiary'))
      .lineHeight(Tokens.lineMicro)
      .width('100%')
      .padding({ bottom: 12 })
  }

  @Builder
  keyPaste() {
    Column({ space: 8 }) {
      TextArea({
        text: this.inputKey,
        placeholder: '粘贴 crsr_… Key'
      })
        .height(88)
        .width('100%')
        .fontSize(Tokens.typeCallout)
        .fontFamily(Tokens.fontMono)
        .fontColor($r('app.color.text_primary'))
        .placeholderFont({ size: Tokens.typeCallout, weight: FontWeight.Regular })
        .placeholderColor($r('app.color.text_placeholder'))
        .backgroundColor($r('app.color.field_bg'))
        .borderRadius(Tokens.radiusField)
        .padding(12)
        .caretColor($r('app.color.accent'))
        .border({ width: 1, color: $r('app.color.border') })
        .onChange((v: string) => {
          this.inputKey = v;
        })
      Row() {
        PasteButton({ icon: PasteIconStyle.LINES, text: PasteDescription.PASTE })
          .height(Tokens.touchMin)
          .fontSize(Tokens.typeCaption)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent)
          .onClick(async (_e: ClickEvent, result: PasteButtonOnClickResult) => {
            if (result !== PasteButtonOnClickResult.SUCCESS) {
              showToast('未授权读取剪贴板');
              return;
            }
            const text = (await readClipboardText()).trim();
            if (text.length === 0) {
              showToast('剪贴板是空的');
              return;
            }
            this.inputKey = text;
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      if (this.errorMsg.length > 0) {
        Text(this.errorMsg)
          .fontSize(Tokens.typeCaption)
          .fontColor($r('app.color.err'))
          .width('100%')
      }
      HuButton({
        label: this.busy ? '验证中…' : '验证并保存',
        variant: 'primary',
        fillWidth: true,
        isEnabled: !this.busy && this.inputKey.trim().length > 8,
        onTap: async () => {
          this.busy = true;
          this.errorMsg = '';
          const ok: boolean = await this.session.saveAndValidate(this.inputKey);
          this.pull();
          if (ok) {
            this.inputKey = '';
            this.showReplace = false;
            showToast('已保存');
            this.navStack.pop();
          } else {
            notifyResult(false, '', this.session.errorMsg.length > 0 ?
              this.session.errorMsg : '验证失败');
          }
        }
      })
    }
    .width('100%')
    .padding({ top: 8, bottom: 12 })
  }

  @Builder
  typeSeg(value: string, label: string) {
    Text(label)
      .fontSize(Tokens.typeCaption)
      .fontWeight(this.typePref === value ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.typePref === value ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
      .width('100%')
      .height(30)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.typePref === value ? $r('app.color.bg1') : Color.Transparent)
      .borderRadius(8)
      .animation({ duration: motionMs(), curve: Curve.FastOutSlowIn })
      .onClick(async () => {
        Haptics.toggle();
        this.typePref = value;
        if (value === 'small') {
          await ReadPrefStore.getInstance().setType('small');
        } else if (value === 'large') {
          await ReadPrefStore.getInstance().setType('large');
        } else {
          await ReadPrefStore.getInstance().setType('default');
        }
      })
  }

  @Builder
  themeSeg(value: string, label: string) {
    Text(label)
      .fontSize(Tokens.typeCaption)
      .fontWeight(this.themePref === value ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.themePref === value ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
      .width('100%')
      .height(30)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.themePref === value ? $r('app.color.bg1') : Color.Transparent)
      .borderRadius(8)
      .animation({ duration: motionMs(), curve: Curve.FastOutSlowIn })
      .onClick(async () => {
        Haptics.toggle();
        this.themePref = value;
        const ctx = getContext(this) as common.UIAbilityContext;
        await ThemeStore.getInstance().setPref(value as ThemePref, ctx.getApplicationContext());
      })
  }
}
