const QUOTE_ID = TextMenuItemId.of('hm-quote');

function isAskXiaoyi(id: TextMenuItemId): boolean {
  if (id.equals(TextMenuItemId.askAI)) {
    return true;
  }
  if (id.equals(TextMenuItemId.AI_WRITER)) {
    return true;
  }
  return false;
}

function selectedSlice(source: string, range: TextRange): string {
  let start = 0;
  let end = source.length;
  if (range.start !== undefined) {
    start = range.start as number;
  }
  if (range.end !== undefined) {
    end = range.end as number;
  }
  if (start >= 0 && end > start && end <= source.length) {
    return source.substring(start, end);
  }
  return source;
}

/**
 * Keep the system selection menu (copy / translate), drop 问问小艺,
 * append 引用. Quote work is deferred so the menu can tear down first.
 */
export function makeQuoteEditMenu(source: string, onQuote: (text: string) => void): EditMenuOptions {
  const menu: EditMenuOptions = {
    onCreateMenu: (menuItems: Array<TextMenuItem>): Array<TextMenuItem> => {
      const next: TextMenuItem[] = [];
      for (let i = 0; i < menuItems.length; i++) {
        if (isAskXiaoyi(menuItems[i].id)) {
          continue;
        }
        next.push(menuItems[i]);
      }
      next.push({
        content: '引用',
        id: QUOTE_ID,
        icon: $r('app.media.ic_quote')
      });
      return next;
    },
    onMenuItemClick: (menuItem: TextMenuItem, range: TextRange): boolean => {
      if (!menuItem.id.equals(QUOTE_ID)) {
        return false;
      }
      let t = selectedSlice(source, range).trim();
      if (t.length === 0) {
        t = source.trim();
      }
      const quoted = t;
      setTimeout(() => {
        if (quoted.length > 0) {
          onQuote(quoted);
        }
      }, 80);
      return true;
    }
  };
  return menu;
}
