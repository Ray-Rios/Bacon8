// File upload types for TypeScript
export interface FileData {
  name: string;
  type: string;
  size: number;
  data: string | ArrayBuffer | null;
  lastModified: number;
}