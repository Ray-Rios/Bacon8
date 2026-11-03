/**
 * Chat history buffer and navigation for Bacon World chat (EverQuest style).
 * Recalls previously sent messages with ArrowUp and navigates back with ArrowDown.
 */
export class ChatHistory {
  private history: string[] = [];
  private index: number = -1;
  private draft: string = '';
  private readonly maxEntries: number;

  constructor(maxEntries: number = 50) {
    this.maxEntries = maxEntries;
  }

  get entries(): readonly string[] {
    return this.history;
  }

  get currentIndex(): number {
    return this.index;
  }

  /**
   * Pushes a sent message into history and resets navigation.
   * Avoids repeating the same message consecutively.
   */
  push(message: string): void {
    const trimmed = message.trim();
    if (!trimmed) return;

    if (this.history.length === 0 || this.history[this.history.length - 1] !== message) {
      this.history.push(message);
      if (this.history.length > this.maxEntries) {
        this.history.shift();
      }
    }
    this.resetNavigation();
  }

  /** Resets navigation back to the uncommitted draft state. */
  resetNavigation(): void {
    this.index = -1;
    this.draft = '';
  }

  /**
   * Navigates history:
   * - direction -1 (ArrowUp): older messages
   * - direction 1 (ArrowDown): newer messages, eventually restoring draft
   *
   * Returns the string to display in the input, or null if no navigation occurred.
   */
  navigate(direction: -1 | 1, currentValue: string): string | null {
    if (this.history.length === 0) return null;

    if (direction === -1) {
      if (this.index === -1) {
        this.draft = currentValue;
        this.index = this.history.length - 1;
        return this.history[this.index];
      }
      if (this.index > 0) {
        this.index--;
        return this.history[this.index];
      }
      // Already at the oldest message
      return this.history[0];
    } else {
      if (this.index === -1) {
        return null;
      }
      if (this.index < this.history.length - 1) {
        this.index++;
        return this.history[this.index];
      }
      // Navigating forward past newest entry restores the user's draft
      const draft = this.draft;
      this.resetNavigation();
      return draft;
    }
  }
}
