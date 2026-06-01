import { Controller } from "@hotwired/stimulus";

// Counts down to a target time and writes a DD:HH:MM:SS string into the
// `time` target. Used for the locked "hardware projects" slot on the project
// creation dialog, which stays unclickable until the target passes.
export default class extends Controller {
  static targets = ["time"];
  static values = { targetIso: String };

  connect() {
    this.targetMs = new Date(this.targetIsoValue).getTime();
    if (Number.isNaN(this.targetMs)) return;
    this.tick();
    this.timer = setInterval(() => this.tick(), 1000);
  }

  disconnect() {
    if (this.timer) clearInterval(this.timer);
  }

  tick() {
    const deltaSec = Math.max(
      0,
      Math.floor((this.targetMs - Date.now()) / 1000),
    );
    const days = Math.floor(deltaSec / 86400);
    const hours = Math.floor((deltaSec % 86400) / 3600);
    const mins = Math.floor((deltaSec % 3600) / 60);
    const secs = deltaSec % 60;
    const pad = (n) => String(n).padStart(2, "0");

    if (this.hasTimeTarget) {
      this.timeTarget.textContent =
        `${pad(days)}:${pad(hours)}:${pad(mins)}:${pad(secs)}`;
    }

    if (deltaSec <= 0 && this.timer) clearInterval(this.timer);
  }
}
