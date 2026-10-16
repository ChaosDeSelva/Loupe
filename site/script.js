const thrust = document.querySelector('#thrust');
const value = document.querySelector('#value');
const trail = document.querySelector('#trail');
function updateThrust() {
  value.value = thrust.value;
  trail.style.width = `${Number(thrust.value) / 2.5}px`;
}
thrust.addEventListener('input', updateThrust);
document.querySelector('#reset').addEventListener('click', () => {
  thrust.value = '240';
  updateThrust();
});
document.querySelector('#copy').addEventListener('click', async () => {
  const status = document.querySelector('#copy-status');
  try {
    await navigator.clipboard.writeText(document.querySelector('#snippet').textContent);
    status.textContent = 'Copied. Paste at the end of main.lua.';
  } catch {
    status.textContent = 'Select the three lines above and copy them manually.';
  }
});
updateThrust();

// The gallery uses the original files, rather than enlarging thumbnail captures.
const previews = [...document.querySelectorAll('.image-preview')];
const viewer = document.querySelector('#image-viewer');
const viewerImage = document.querySelector('#viewer-image');
const viewerStage = document.querySelector('.viewer-stage');
const zoomButton = document.querySelector('#viewer-zoom');
let imageIndex = 0;
let returnFocus;
function setZoom(zoomed) {
  viewerStage.classList.toggle('zoomed', zoomed);
  zoomButton.setAttribute('aria-pressed', String(zoomed));
  zoomButton.textContent = zoomed ? 'Fit to screen' : 'Actual pixels';
  viewerStage.scrollTop = viewerStage.scrollLeft = 0;
}
function showImage(index) {
  imageIndex = (index + previews.length) % previews.length;
  const link = previews[imageIndex];
  const source = link.querySelector('img');
  viewerImage.src = link.href;
  viewerImage.alt = source.alt;
  viewerImage.style.setProperty('--image-width', (source.src.includes('.svg') ? Math.max(source.naturalWidth, window.innerWidth) : source.naturalWidth) + 'px');
  document.querySelector('#viewer-original').href = link.href;
  document.querySelector('#viewer-caption').textContent = source.closest('figure')?.querySelector('figcaption')?.textContent || source.alt;
  document.querySelector('#viewer-count').textContent = `${imageIndex + 1} / ${previews.length}`;
  setZoom(false);
}
previews.forEach((link, index) => {
  link.addEventListener('click', event => {
    if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    returnFocus = link;
    showImage(index);
    viewer.showModal();
    document.body.classList.add('viewing-image');
    document.querySelector('#viewer-close').focus();
  });
});
document.querySelector('#viewer-close').addEventListener('click', () => viewer.close());
document.querySelector('#viewer-prev').addEventListener('click', () => showImage(imageIndex - 1));
document.querySelector('#viewer-next').addEventListener('click', () => showImage(imageIndex + 1));
zoomButton.addEventListener('click', () => setZoom(!viewerStage.classList.contains('zoomed')));
viewerImage.addEventListener('click', () => zoomButton.click());
viewerStage.addEventListener('click', event => { if (event.target === viewerStage) viewer.close(); });
viewer.addEventListener('keydown', event => {
  if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
    event.preventDefault();
    showImage(imageIndex + (event.key === 'ArrowRight' ? 1 : -1));
  }
});
viewer.addEventListener('close', () => {
  document.body.classList.remove('viewing-image');
  returnFocus?.focus();
});
