import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { WidgetBridge } from '../utils/WidgetBridge';
import { Log } from '../utils/Log';

const TAG = 'EntryFormAbility';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const raw = want.parameters;
    const formId = raw && raw[formInfo.FormParam.IDENTITY_KEY] ? `${raw[formInfo.FormParam.IDENTITY_KEY]}` : '';
    this.fillLater(formId);
    return WidgetBridge.emptyBind();
  }

  onUpdateForm(formId: string): void {
    this.fillLater(formId);
  }

  onRemoveForm(formId: string): void {
    WidgetBridge.removeForm(this.context, formId).catch(() => {
    });
  }

  private fillLater(formId: string): void {
    WidgetBridge.addForm(this.context, formId).then(async () => {
      const snap = await WidgetBridge.read(this.context);
      if (formId.length > 0) {
        await formProvider.updateForm(formId, WidgetBridge.bind(snap));
      }
    }).catch((e: Object) => {
      Log.warn(TAG, `fill failed: ${JSON.stringify(e)}`);
    });
  }
}
