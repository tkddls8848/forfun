import dynamic from 'next/dynamic';

export default function DynamicComponent({
  component,
  loading: LoadingComponent,
  fallback,
}) {
  const DynamicLoadedComponent = dynamic(component, {
    loading: LoadingComponent
      ? () => <LoadingComponent />
      : () => fallback || <div>Loading...</div>,
    ssr: false, // 클라이언트 사이드에서만 렌더링
  });

  return <DynamicLoadedComponent />;
} 