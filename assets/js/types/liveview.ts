// LiveView Hook types for TypeScript
export interface LiveViewHook {
  el: HTMLElement;
  pushEvent: (event: string, payload: any) => void;
  mounted?: () => void;
  updated?: () => void;
  destroyed?: () => void;
  disconnected?: () => void;
  reconnected?: () => void;
}