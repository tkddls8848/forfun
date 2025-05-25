import Image from 'next/image';
import { useState } from 'react';

export default function OptimizedImage({
  src,
  alt,
  width,
  height,
  className = '',
  priority = false,
}) {
  const [isLoading, setIsLoading] = useState(true);

  return (
    <div className={`relative ${className}`}>
      <Image
        src={src}
        alt={alt}
        width={width}
        height={height}
        className={`
          duration-700 ease-in-out
          ${isLoading ? 'scale-110 blur-2xl grayscale' : 'scale-100 blur-0 grayscale-0'}
        `}
        onLoadingComplete={() => setIsLoading(false)}
        priority={priority}
        quality={75}
      />
    </div>
  );
} 