'use client';

import Image from 'next/image';

export default function ProductItem({ name, subTitle, description, features, imageUrl, linkUrl }) {
  return (
    <div className="product">
      <div className="product_name">
        <h3>
          {name.split('<br>').map((line, i, arr) => (
            <span key={i}>
              {line}
              {i < arr.length - 1 && <br />}
            </span>
          ))}
        </h3>
        <p>
          <strong>{subTitle}</strong>
        </p>
      </div>
      <div className="product_info">
        <i></i>
        <p>{description}</p>
        <p className="list">
          {features.map((feature, index) => (
            <span key={index}>{feature}</span>
          ))}
        </p>
        <div>
          <a href={linkUrl} target="_blank" rel="noreferrer">자세히보기</a>
        </div>
      </div>
      <div className="product_img">
        <Image 
          src={imageUrl} 
          alt={name.replace(/<br>/g, ' ')} 
          width={300} 
          height={400}
          style={{
            maxWidth: '100%',
            maxHeight: '200px',
            objectFit: 'contain'
          }}
        />
      </div>
    </div>
  );
}
