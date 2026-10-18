export const Sortable = {
  mounted() {
    const el = this.el as HTMLElement;
    const group = el.dataset.group;
    
    // Add dragstart listener to the container to handle bubbling events from items
    el.addEventListener('dragstart', (e: DragEvent) => {
      const target = e.target as HTMLElement;
      // Find the closest draggable item (li)
      const item = target.closest('[draggable="true"]') as HTMLElement;
      
      if (item) {
        item.classList.add('dragging');
        item.style.opacity = '0.5';
        e.dataTransfer?.setData('text/plain', item.dataset.id || '');
        e.dataTransfer?.setData('group', group || '');
        // Set drag effect
        if (e.dataTransfer) e.dataTransfer.effectAllowed = 'move';
      }
    });

    el.addEventListener('dragend', (e: DragEvent) => {
      const target = e.target as HTMLElement;
      const item = target.closest('[draggable="true"]') as HTMLElement;
      if (item) {
        item.classList.remove('dragging');
        item.style.opacity = '1';
      }
      
      // Remove any drop indicators
      el.querySelectorAll('.drag-over').forEach(i => i.classList.remove('drag-over'));
    });

    el.addEventListener('dragover', (e: DragEvent) => {
      e.preventDefault(); // Allow dropping
      const draggingItem = el.querySelector('.dragging') as HTMLElement;
      if (!draggingItem) return;

      const siblings = [...el.querySelectorAll('[draggable="true"]:not(.dragging)')];
      
      // Find the sibling after which the dragging item should be placed
      const nextSibling = siblings.find(sibling => {
        const box = sibling.getBoundingClientRect();
        return e.clientY <= box.top + box.height / 2;
      });
      
      if (nextSibling) {
        el.insertBefore(draggingItem, nextSibling);
      } else {
        el.appendChild(draggingItem);
      }
    });

    el.addEventListener('drop', (e: DragEvent) => {
      e.preventDefault();
      const draggedGroup = e.dataTransfer?.getData('group');
      
      // Only allow dropping within the same group
      if (draggedGroup !== group) return;

      const items = [...el.querySelectorAll('[draggable="true"]')];
      // Map to IDs and filter out any undefined/null/empty values
      const newOrder = items
        .map(item => (item as HTMLElement).dataset.id)
        .filter(id => id);
      
      console.log("Reordering channels:", newOrder);

      this.pushEvent("reorder_channels", { 
        group: group,
        ids: newOrder 
      });
    });
  }
}
