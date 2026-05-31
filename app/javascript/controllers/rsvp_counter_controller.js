import { Controller } from "@hotwired/stimulus";

// Odometer-style counter: each digit animates independently. When the
// count jumps by more than 1 (batched broadcasts), intermediate values
// are queued and ticked through with faster, jittered timing so bursts
// of signups look organic rather than a single jump.
export default class extends Controller {
  connect() {
    this.prefersReducedMotion =
      window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;

    this.span = this.element.querySelector("#rsvp_counter");
    if (!this.span) return;

    this.currentCount = parseInt(this.span.dataset.count, 10) || 0;
    this.animating = false;
    this.queue = [];
    this.tickDuration = null;
    this.buildDigits(this.currentCount);

    this._onStream = this.onStream.bind(this);
    document.addEventListener("turbo:before-stream-render", this._onStream);
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this._onStream);
  }

  formatNumber(n) {
    return n.toLocaleString();
  }

  buildDigits(count) {
    const text = this.formatNumber(count);
    this.span.textContent = "";
    this.span.setAttribute("aria-label", text);
    this.span.dataset.count = count;
    this.digitEls = [];

    for (const ch of text) {
      const wrapper = document.createElement("span");
      wrapper.className = /\d/.test(ch)
        ? "rsvp-counter__digit"
        : "rsvp-counter__sep";

      const inner = document.createElement("span");
      inner.className = "rsvp-counter__digit-inner";
      inner.textContent = ch;
      wrapper.appendChild(inner);

      this.span.appendChild(wrapper);
      this.digitEls.push({ wrapper, inner, value: ch });
    }
  }

  onStream(event) {
    const stream = event.target;
    if (stream?.getAttribute?.("target") !== "rsvp_counter") return;

    const template = stream.querySelector("template");
    const incoming = template?.content.querySelector("#rsvp_counter");
    if (!incoming) return;

    const newCount = parseInt(incoming.dataset.count, 10);
    if (Number.isNaN(newCount) || newCount === this.currentCount) return;

    event.preventDefault();

    if (newCount < this.currentCount) {
      this.currentCount = newCount;
      this.buildDigits(newCount);
      return;
    }

    const oldCount = this.currentCount;
    this.currentCount = newCount;

    const delta = newCount - oldCount;
    if (delta <= 1) {
      this.tickDuration = null;
      this.enqueue(newCount);
    } else {
      const maxTicks = Math.min(delta, 20);
      this.tickDuration = Math.max(80, Math.floor(1000 / maxTicks));
      const step = delta / maxTicks;
      for (let i = 1; i <= maxTicks; i++) {
        this.enqueue(Math.round(oldCount + step * i));
      }
    }
  }

  enqueue(count) {
    if (this.animating) {
      this.queue.push(count);
    } else {
      this.animateToCount(count);
    }
  }

  animateToCount(count) {
    this.animating = true;

    const newText = this.formatNumber(count);
    const oldText = this.digitEls.map((d) => d.value).join("");

    if (newText.length !== oldText.length) {
      this.buildDigits(count);
      this.pulse();
      this.animating = false;
      this.drain();
      return;
    }

    const base = this.tickDuration || 680;
    const jitter = this.tickDuration ? base * (0.5 + Math.random()) : base;
    const duration = Math.round(jitter);

    const animations = [];
    for (let i = 0; i < newText.length; i++) {
      if (newText[i] !== this.digitEls[i].value) {
        animations.push(this.animateDigit(this.digitEls[i], newText[i], duration));
      }
    }

    if (animations.length === 0) {
      this.animating = false;
      this.drain();
      return;
    }

    this.pulse();

    if (this.prefersReducedMotion) {
      this.span.setAttribute("aria-label", newText);
      this.span.dataset.count = count;
      this.animating = false;
      if (this.queue.length === 0) this.tickDuration = null;
      this.drain();
      return;
    }

    Promise.all(animations).then(() => {
      this.span.setAttribute("aria-label", newText);
      this.span.dataset.count = count;
      this.animating = false;
      if (this.queue.length === 0) this.tickDuration = null;
      this.drain();
    });
  }

  animateDigit(digitObj, newValue, duration) {
    if (this.prefersReducedMotion) {
      digitObj.inner.textContent = newValue;
      digitObj.value = newValue;
      return Promise.resolve();
    }

    return new Promise((resolve) => {
      const oldInner = digitObj.inner;
      oldInner.classList.add("rsvp-counter__digit-inner--exiting");
      oldInner.style.animationDuration = `${duration}ms`;

      const newInner = document.createElement("span");
      newInner.className =
        "rsvp-counter__digit-inner rsvp-counter__digit-inner--entering";
      newInner.textContent = newValue;
      newInner.style.animationDuration = `${duration}ms`;
      digitObj.wrapper.appendChild(newInner);

      newInner.addEventListener(
        "animationend",
        () => {
          oldInner.remove();
          newInner.classList.remove("rsvp-counter__digit-inner--entering");
          newInner.style.animationDuration = "";
          digitObj.inner = newInner;
          digitObj.value = newValue;
          resolve();
        },
        { once: true },
      );
    });
  }

  drain() {
    if (this.queue.length > 0) {
      this.animateToCount(this.queue.shift());
    }
  }

  pulse() {
    this.span.classList.remove("rsvp-counter--tick");
    void this.span.offsetWidth;
    this.span.classList.add("rsvp-counter--tick");
  }
}
