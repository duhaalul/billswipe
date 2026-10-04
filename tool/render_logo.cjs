const fs = require('fs');
// Optional asset regeneration: npm install --no-save --package-lock=false sharp
const sharp = require('sharp');
(async()=> {
 const original = fs.readFileSync('assets/billswipe-logo.svg','utf8');
 await sharp(Buffer.from(original.replace('width="100%"','width="500"'))).resize(1000,300).png().toFile('assets/billswipe-logo.png');
 const icon = original.replace('viewBox="0 0 500 150" width="100%" height="150"','viewBox="-25 -25 210 210" width="1024" height="1024"').replace(/<text[\s\S]*?<\/text>/,'');
 fs.writeFileSync('assets/billswipe-icon.svg',icon);
 await sharp(Buffer.from(icon)).flatten({background:'#ffffff'}).png().toFile('assets/billswipe-icon.png');
 for(const [density,size] of Object.entries({mdpi:48,hdpi:72,xhdpi:96,xxhdpi:144,xxxhdpi:192})) await sharp('assets/billswipe-icon.png').resize(size,size).toFile(`android/app/src/main/res/mipmap-${density}/ic_launcher.png`);
 const contents=JSON.parse(fs.readFileSync('ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json','utf8'));
 for(const item of contents.images) if(item.filename) { const size=Math.round(parseFloat(item.size)*parseFloat(item.scale)); await sharp('assets/billswipe-icon.png').resize(size,size).toFile('ios/Runner/Assets.xcassets/AppIcon.appiconset/'+item.filename); }
 for(const size of [192,512]) for(const name of [`Icon-${size}.png`,`Icon-maskable-${size}.png`]) await sharp('assets/billswipe-icon.png').resize(size,size).toFile('web/icons/'+name);
 await sharp('assets/billswipe-icon.png').resize(32,32).toFile('web/favicon.png');
})();
