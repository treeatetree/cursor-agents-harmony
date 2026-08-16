import { CustomSubagentDef, EnvVarDef, McpServerDef } from '../models/Api';
import { Tokens } from '../theme/Tokens';
import { emptyEnvVar, emptyMcp, emptySubagent } from '../utils/AgentCapabilities';
import { HuChip } from './HuChip';
import { HuTextButton } from './HuTextButton';

@Component
export struct McpListEditor {
  @Link servers: McpServerDef[];
  @State private advancedAt: number = -1;

  build() {
    Column({ space: 8 }) {
      if (this.servers.length === 0) {
        Text('还没有 MCP。点添加后填名称和地址即可。')
          .fontSize(Tokens.typeCaption)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      }
      ForEach(this.servers, (s: McpServerDef, idx: number) => {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            TextInput({ text: s.name, placeholder: '名称' })
              .layoutWeight(1)
              .height(Tokens.touchMin)
              .fontSize(Tokens.typeCallout)
              .backgroundColor($r('app.color.field_bg'))
              .borderRadius(Tokens.radiusField)
              .onChange((v: string) => {
                this.patch(idx, 'name', v);
              })
            Text('删除')
              .fontSize(Tokens.typeCaption)
              .fontColor($r('app.color.err'))
              .constraintSize({ minHeight: Tokens.touchMin, minWidth: Tokens.touchMin })
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.removeAt(idx);
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          if (s.type !== 'stdio') {
            TextInput({ text: s.url, placeholder: 'https://…/mcp' })
              .height(Tokens.touchMin)
              .width('100%')
              .fontSize(Tokens.typeCallout)
              .backgroundColor($r('app.color.field_bg'))
              .borderRadius(Tokens.radiusField)
              .onChange((v: string) => {
                this.patch(idx, 'url', v);
              })
          } else {
            TextInput({ text: s.command, placeholder: 'command，如 npx' })
              .height(Tokens.touchMin)
              .width('100%')
              .fontSize(Tokens.typeCallout)
              .backgroundColor($r('app.color.field_bg'))
              .borderRadius(Tokens.radiusField)
              .onChange((v: string) => {
                this.patch(idx, 'command', v);
              })
          }
          Row() {
            HuTextButton({
              label: this.advancedAt === idx ? '收起' : '高级',
              color: $r('app.color.text_secondary'),
              compact: true,
              onTap: () => {
                this.advancedAt = this.advancedAt === idx ? -1 : idx;
              }
            })
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
          if (this.advancedAt === idx) {
            Row({ space: 8 }) {
              HuChip({
                label: 'HTTP',
                on: s.type === 'http',
                onTap: () => {
                  this.patch(idx, 'type', 'http');
                }
              })
              HuChip({
                label: 'SSE',
                on: s.type === 'sse',
                onTap: () => {
                  this.patch(idx, 'type', 'sse');
                }
              })
              HuChip({
                label: 'stdio',
                on: s.type === 'stdio',
                onTap: () => {
                  this.patch(idx, 'type', 'stdio');
                }
              })
            }
            .width('100%')
            if (s.type === 'stdio') {
              TextInput({ text: s.argsText, placeholder: '参数，空格分隔' })
                .height(Tokens.touchMin)
                .width('100%')
                .fontSize(Tokens.typeCallout)
                .backgroundColor($r('app.color.field_bg'))
                .borderRadius(Tokens.radiusField)
                .onChange((v: string) => {
                  this.patch(idx, 'argsText', v);
                })
              TextInput({ text: s.envText, placeholder: '环境变量 KEY=VAL;KEY=VAL' })
                .height(Tokens.touchMin)
                .width('100%')
                .fontSize(Tokens.typeCallout)
                .backgroundColor($r('app.color.field_bg'))
                .borderRadius(Tokens.radiusField)
                .onChange((v: string) => {
                  this.patch(idx, 'envText', v);
                })
            } else {
              TextInput({ text: s.headersText, placeholder: '请求头 Authorization=Bearer …' })
                .height(Tokens.touchMin)
                .width('100%')
                .fontSize(Tokens.typeCallout)
                .backgroundColor($r('app.color.field_bg'))
                .borderRadius(Tokens.radiusField)
                .onChange((v: string) => {
                  this.patch(idx, 'headersText', v);
                })
            }
          }
        }
        .width('100%')
      }, (s: McpServerDef, idx: number) => `mcp-${idx}-${s.type}`)
      HuChip({
        label: this.servers.length === 0 ? '添加 MCP' : '再加一个',
        on: false,
        onTap: () => {
          if (this.servers.length >= 50) {
            return;
          }
          const next = this.servers.slice();
          next.push(emptyMcp());
          this.servers = next;
          this.advancedAt = -1;
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private patch(idx: number, field: string, value: string): void {
    if (idx < 0 || idx >= this.servers.length) {
      return;
    }
    const next = this.servers.slice();
    const cur = next[idx];
    const copy: McpServerDef = {
      name: field === 'name' ? value : cur.name,
      type: field === 'type' ? value : cur.type,
      url: field === 'url' ? value : cur.url,
      command: field === 'command' ? value : cur.command,
      argsText: field === 'argsText' ? value : cur.argsText,
      envText: field === 'envText' ? value : cur.envText,
      headersText: field === 'headersText' ? value : cur.headersText
    };
    next[idx] = copy;
    this.servers = next;
  }

  private removeAt(idx: number): void {
    const next: McpServerDef[] = [];
    for (let i = 0; i < this.servers.length; i++) {
      if (i !== idx) {
        next.push(this.servers[i]);
      }
    }
    this.servers = next;
    if (this.advancedAt === idx) {
      this.advancedAt = -1;
    }
  }
}

@Component
export struct SubagentListEditor {
  @Link items: CustomSubagentDef[];

  build() {
    Column({ space: 8 }) {
      ForEach(this.items, (s: CustomSubagentDef, idx: number) => {
        Column({ space: 6 }) {
          Row() {
            Text(s.name.trim().length > 0 ? s.name : `子代理 ${idx + 1}`)
              .fontSize(Tokens.typeCaption)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
            Text('删除')
              .fontSize(Tokens.typeCaption)
              .fontColor($r('app.color.err'))
              .constraintSize({ minHeight: Tokens.touchMin })
              .onClick(() => {
                this.removeAt(idx);
              })
          }
          .width('100%')
          TextInput({ text: s.name, placeholder: '名称，勿与 explore/debug 冲突' })
            .height(Tokens.touchMin)
            .width('100%')
            .fontSize(Tokens.typeCallout)
            .backgroundColor($r('app.color.field_bg'))
            .borderRadius(Tokens.radiusField)
            .onChange((v: string) => {
              this.patch(idx, 'name', v);
            })
          TextInput({ text: s.description, placeholder: '一句话描述' })
            .height(Tokens.touchMin)
            .width('100%')
            .fontSize(Tokens.typeCallout)
            .backgroundColor($r('app.color.field_bg'))
            .borderRadius(Tokens.radiusField)
            .onChange((v: string) => {
              this.patch(idx, 'description', v);
            })
          TextArea({ text: s.prompt, placeholder: '人设 / 任务说明' })
            .height(72)
            .width('100%')
            .fontSize(Tokens.typeCallout)
            .backgroundColor($r('app.color.field_bg'))
            .borderRadius(Tokens.radiusField)
            .onChange((v: string) => {
              this.patch(idx, 'prompt', v);
            })
          TextInput({ text: s.model, placeholder: '模型，默认 inherit' })
            .height(Tokens.touchMin)
            .width('100%')
            .fontSize(Tokens.typeCallout)
            .backgroundColor($r('app.color.field_bg'))
            .borderRadius(Tokens.radiusField)
            .onChange((v: string) => {
              this.patch(idx, 'model', v);
            })
        }
        .width('100%')
        .padding(10)
        .backgroundColor($r('app.color.bg0'))
        .borderRadius(Tokens.radiusMd)
      }, (s: CustomSubagentDef, idx: number) => `sub-${idx}-${s.name}`)
      HuChip({
        label: '添加',
        on: false,
        onTap: () => {
          if (this.items.length >= 20) {
            return;
          }
          const next = this.items.slice();
          next.push(emptySubagent());
          this.items = next;
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private patch(idx: number, field: string, value: string): void {
    if (idx < 0 || idx >= this.items.length) {
      return;
    }
    const next = this.items.slice();
    const cur = next[idx];
    next[idx] = {
      name: field === 'name' ? value : cur.name,
      description: field === 'description' ? value : cur.description,
      prompt: field === 'prompt' ? value : cur.prompt,
      model: field === 'model' ? value : cur.model
    };
    this.items = next;
  }

  private removeAt(idx: number): void {
    const next: CustomSubagentDef[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (i !== idx) {
        next.push(this.items[i]);
      }
    }
    this.items = next;
  }
}

@Component
export struct EnvVarListEditor {
  @Link items: EnvVarDef[];

  build() {
    Column({ space: 8 }) {
      Text('不能以 CURSOR_ 开头。有变量时不会带客户端 agentId。')
        .fontSize(Tokens.typeMicro)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
      ForEach(this.items, (v: EnvVarDef, idx: number) => {
        Row({ space: 8 }) {
          TextInput({ text: v.key, placeholder: 'KEY' })
            .layoutWeight(1)
            .height(Tokens.touchMin)
            .fontSize(Tokens.typeCallout)
            .backgroundColor($r('app.color.field_bg'))
            .borderRadius(Tokens.radiusField)
            .onChange((val: string) => {
              this.patch(idx, true, val);
            })
          TextInput({ text: v.value, placeholder: 'value' })
            .layoutWeight(1)
            .height(Tokens.touchMin)
            .fontSize(Tokens.typeCallout)
            .backgroundColor($r('app.color.field_bg'))
            .borderRadius(Tokens.radiusField)
            .onChange((val: string) => {
              this.patch(idx, false, val);
            })
          Text('删除')
            .fontSize(Tokens.typeCaption)
            .fontColor($r('app.color.err'))
            .constraintSize({ minHeight: Tokens.touchMin })
            .onClick(() => {
              this.removeAt(idx);
            })
        }
        .width('100%')
      }, (v: EnvVarDef, idx: number) => `var-${idx}-${v.key}`)
      HuChip({
        label: '添加',
        on: false,
        onTap: () => {
          if (this.items.length >= 50) {
            return;
          }
          const next = this.items.slice();
          next.push(emptyEnvVar());
          this.items = next;
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private patch(idx: number, isKey: boolean, value: string): void {
    if (idx < 0 || idx >= this.items.length) {
      return;
    }
    const next = this.items.slice();
    next[idx] = {
      key: isKey ? value : next[idx].key,
      value: isKey ? next[idx].value : value
    };
    this.items = next;
  }

  private removeAt(idx: number): void {
    const next: EnvVarDef[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (i !== idx) {
        next.push(this.items[i]);
      }
    }
    this.items = next;
  }
}
