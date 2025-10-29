<script lang="ts">
  import { onMount, onDestroy, setContext } from 'svelte';
  import Lenis from '@studio-freight/lenis';

  type LenisController = {
    start: () => void;
    stop: () => void;
  };

  let lenis: Lenis | null = null;
  let frameId: number | null = null;

  const easing = (t: number) => Math.min(1, 1.001 - Math.pow(2, -10 * t));

  const lenisController: LenisController = {
    start: () => lenis?.start(),
    stop: () => lenis?.stop()
  };

  setContext('lenis', lenisController);

  const initLenis = () => {
    lenis = new Lenis({
      duration: 1.2,
      easing,
      smoothWheel: true,
      smoothTouch: false
    });

    const raf = (time: number) => {
      lenis?.raf(time);
      frameId = requestAnimationFrame(raf);
    };

    frameId = requestAnimationFrame(raf);
  };

  const destroyLenis = () => {
    if (frameId !== null) {
      cancelAnimationFrame(frameId);
      frameId = null;
    }

    lenis?.destroy();
    lenis = null;
  };

  onMount(() => {
    if (typeof history !== 'undefined' && 'scrollRestoration' in history) {
      history.scrollRestoration = 'manual';
    }

    initLenis();

    return () => {
      destroyLenis();
    };
  });

  onDestroy(() => {
    destroyLenis();
  });
</script>

<!--
  Root layout that wires Lenis once so smooth scrolling is available on every page.
  Adjust the "duration" or "easing" options above to tweak the feel of the scroll.
  Access the Lenis controller from child components with `const lenis = getContext('lenis')` to
  temporarily stop/start scrolling (useful for modals or overlays).
-->

<slot />
