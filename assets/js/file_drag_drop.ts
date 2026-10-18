// File Drag & Drop Hook for Phoenix LiveView

import { LiveViewHook } from './types/liveview';
import { FileData } from './types/file-upload';

type FileDragDropHook = LiveViewHook;
type FileUploadHook = LiveViewHook;

export const FileDragDrop: FileDragDropHook = {
  mounted() {
    // eslint-disable-next-line @typescript-eslint/no-this-alias
    const hook = this; // Capture hook context for use in callbacks
    
    // For file manager component, the drop zone is the element itself
    const dropZone = this.el.id?.includes('drop-zone') ? this.el : this.el.querySelector('[id*="drop-zone"]') as HTMLElement;
    const dropOverlay = this.el.querySelector('[id*="drop-overlay"]') as HTMLElement;
    
    if (!dropZone) {
      console.error('FileDragDrop: Drop zone not found');
      return;
    }

    // Prevent default drag behaviors
    (['dragenter', 'dragover', 'dragleave', 'drop'] as const).forEach(eventName => {
      dropZone.addEventListener(eventName, preventDefaults, false);
      document.body.addEventListener(eventName, preventDefaults, false);
    });

    // Highlight drop zone when item is dragged over it
    (['dragenter', 'dragover'] as const).forEach(eventName => {
      dropZone.addEventListener(eventName, highlight, false);
    });

    (['dragleave', 'drop'] as const).forEach(eventName => {
      dropZone.addEventListener(eventName, unhighlight, false);
    });

    // Handle dropped files
    dropZone.addEventListener('drop', handleDrop, false);
    
    // Handle file input change (if present)
    const fileInput = this.el.querySelector('#file-upload') as HTMLInputElement;
    if (fileInput) {
      fileInput.addEventListener('change', handleFileSelect, false);
    }

    function preventDefaults(e: Event): void {
      e.preventDefault();
      e.stopPropagation();
    }

    function highlight(_e: Event): void {
      dropZone.classList.add('border-blue-500', 'bg-blue-900/20');
      if (dropOverlay) {
        dropOverlay.classList.remove('hidden');
        dropOverlay.classList.add('flex');
      }
    }

    function unhighlight(_e: Event): void {
      dropZone.classList.remove('border-blue-500', 'bg-blue-900/20');
      if (dropOverlay) {
        dropOverlay.classList.add('hidden');
        dropOverlay.classList.remove('flex');
      }
    }

    function handleDrop(e: DragEvent): void {
      const dt = e.dataTransfer;
      const files = dt?.files;
      if (files) {
        handleFiles(files);
      }
    }

    function handleFileSelect(e: Event): void {
      const target = e.target as HTMLInputElement;
      const files = target.files;
      if (files) {
        handleFiles(files);
      }
    }

    function handleFiles(files: FileList): void {
      const fileArray = Array.from(files);
      
      // Validate files
      const validFiles = fileArray.filter((file: File) => {
        // Check file size (50MB limit)
        if (file.size > 50 * 1024 * 1024) {
          alert(`File "${file.name}" is too large. Maximum size is 50MB.`);
          return false;
        }
        
        // Check file type
        const allowedTypes = [
          'image/jpeg', 'image/png', 'image/gif', 'image/webp',
          'video/mp4', 'video/avi', 'video/mov', 'video/wmv',
          'audio/mp3', 'audio/wav', 'audio/ogg',
          'application/pdf', 'application/msword',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          'text/plain', 'text/csv',
          'application/zip', 'application/x-rar-compressed'
        ];
        
        if (!allowedTypes.includes(file.type)) {
          alert(`File type "${file.type}" is not supported for file "${file.name}".`);
          return false;
        }
        
        return true;
      });

      if (validFiles.length === 0) return;

      // Show upload progress
      showUploadProgress(validFiles);

      // Process files
      validFiles.forEach((file: File, _index: number) => {
        const reader = new FileReader();
        
        reader.onload = (e: ProgressEvent<FileReader>): void => {
          const fileData: FileData = {
            name: file.name,
            type: file.type,
            size: file.size,
            data: e.target?.result || null,
            lastModified: file.lastModified
          };
          
          // Send to LiveView using captured hook reference
          hook.pushEvent("file_drop", { files: [fileData] });
        };
        
        reader.onerror = (e: ProgressEvent<FileReader>): void => {
          console.error('Error reading file:', file.name, e);
          alert(`Error reading file "${file.name}". Please try again.`);
        };
        
        reader.readAsDataURL(file);
      });
    }

    function showUploadProgress(files: File[]): void {
      // Create progress indicator
      const progressDiv = document.createElement('div');
      progressDiv.className = 'fixed top-4 right-4 glass-dark text-white p-4 rounded-lg shadow-lg z-50';
      progressDiv.innerHTML = `
        <div class="flex items-center space-x-2">
          <div class="animate-spin rounded-full h-4 w-4 border-b-2 border-blue-500"></div>
          <span>Uploading ${files.length} file(s)...</span>
        </div>
      `;
      
      document.body.appendChild(progressDiv);
      
      // Remove after 5 seconds
      setTimeout(() => {
        if (progressDiv.parentNode) {
          progressDiv.parentNode.removeChild(progressDiv);
        }
      }, 5000);
    }
  }
} as FileDragDropHook;

// File Upload Hook for traditional file input
export const FileUpload: FileUploadHook = {
  mounted() {
    // eslint-disable-next-line @typescript-eslint/no-this-alias
    const hook = this; // Capture hook context for use in callbacks
    
    this.el.addEventListener('change', (e: Event) => {
      const target = e.target as HTMLInputElement;
      const files = Array.from(target.files || []);
      
      files.forEach((file: File) => {
        const reader = new FileReader();
        
        reader.onload = (event: ProgressEvent<FileReader>): void => {
          const fileData: FileData = {
            name: file.name,
            type: file.type,
            size: file.size,
            data: event.target?.result || null,
            lastModified: file.lastModified
          };
          
          // Use captured hook reference instead of 'this'
          hook.pushEvent("file_selected", fileData);
        };
        
        reader.onerror = (event: ProgressEvent<FileReader>): void => {
          console.error('Error reading file:', file.name, event);
          alert(`Error reading file "${file.name}". Please try again.`);
        };
        
        reader.readAsDataURL(file);
      });
      
      // Clear the input
      target.value = '';
    });
  }
} as FileUploadHook;