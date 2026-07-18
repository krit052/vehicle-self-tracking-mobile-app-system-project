# 🔐 2. ตัวควบคุมการเข้าถึงข้อมูลข้าม Thread ย้ายไปเป็น lock รายกล้องใน CameraContext แล้ว
from config import TYPHOON_OCR_API_KEY, _TYPHOON_OCR_URL, TYPHOON_OCR_MODEL, TYPHOON_OCR_TASK_TYPE, TYPHOON_OCR_MAX_TOKENS, TYPHOON_OCR_TEMPERATURE, TYPHOON_OCR_TOP_P, TYPHOON_OCR_REP_PENALTY, _PLATE_TEXT_MAX_CHARS
import requests as _requests
import cv2
import json
import re
import difflib #เพิ่ม difflib สำหรับการเปรียบเทียบข้อความ เวลา OCR อ่านป้ายทะเบียนผิดพลาดเล็กน้อย จะให้เทียบกับจังหวัดที่เคยเจอในฐานข้อมูล เพื่อให้สามารถจับคู่ได้แม่นยำขึ้น

def _call_typhoon_ocr(img_np) -> str:
    if not TYPHOON_OCR_API_KEY:
        return ""
    success, encoded = cv2.imencode(".jpg", img_np)
    if not success:
        return ""
    try:
        resp = _requests.post(
            _TYPHOON_OCR_URL,
            headers={"Authorization": f"Bearer {TYPHOON_OCR_API_KEY}"},
            files={"file": ("plate.jpg", encoded.tobytes(), "image/jpeg")},
            data={
                "model": TYPHOON_OCR_MODEL,
                "task_type": TYPHOON_OCR_TASK_TYPE,
                "max_tokens": str(TYPHOON_OCR_MAX_TOKENS),
                "temperature": str(TYPHOON_OCR_TEMPERATURE),
                "top_p": str(TYPHOON_OCR_TOP_P),
                "repetition_penalty": str(TYPHOON_OCR_REP_PENALTY),
            },
            timeout=30,
        )
        if resp.status_code != 200:
            print(f"[TyphoonOCR] API error {resp.status_code}: {resp.text[:200]}")
            return ""
        
        texts = []
        for page in resp.json().get("results", []):
            if not isinstance(page, dict):
                continue
            if page.get("success") and page.get("message"):
                try:
                    content = page["message"]["choices"][0]["message"]["content"]
                except (KeyError, IndexError, TypeError, AttributeError):
                    continue
                try:
                    text = json.loads(content).get("natural_text", content)
                except (json.JSONDecodeError, TypeError, AttributeError):
                    text = content
                if text:
                    texts.append(text.strip())
        return "\n".join(texts).strip()
    except Exception as e:
        print("[TyphoonOCR] Connection error:", repr(e))
        return ""


# รายชื่อจังหวัด ในประเทศไทย (ใช้สำหรับการแก้ไขคำเพี้ยนของจังหวัดในป้ายทะเบียน)
THAI_PROVINCES = [
    "กระบี่", "กรุงเทพมหานคร", "กาญจนบุรี", "กาฬสินธุ์", "กำแพงเพชร", 
    "ขอนแก่น", "จันทบุรี", "ฉะเชิงเทรา", "ชลบุรี", "ชัยนาท", 
    "ชัยภูมิ", "ชุมพร", "เชียงราย", "เชียงใหม่", "ตรัง", 
    "ตราด", "ตาก", "นครนายก", "นครปฐม", "นครพนม", 
    "นครราชสีมา", "นครศรีธรรมราช", "นครสวรรค์", "นนทบุรี", "นราธิวาส", 
    "น่าน", "บึงกาฬ", "บุรีรัมย์", "ปทุมธานี", "ประจวบคีรีขันธ์", 
    "ปราจีนบุรี", "ปัตตานี", "พระนครศรีอยุธยา", "พะเยา", "พังงา", 
    "พัทลุง", "พิจิตร", "พิษณุโลก", "เพชรบุรี", "เพชรบูรณ์", 
    "แพร่", "ภูเก็ต", "มหาสารคาม", "มุกดาหาร", "แม่ฮ่องสอน", 
    "ยโสธร", "ยะลา", "ร้อยเอ็ด", "ระนอง", "ระยอง", 
    "ราชบุรี", "ลพบุรี", "ลำปาง", "ลำพูน", "เลย", 
    "ศรีสะเกษ", "สกลนคร", "สงขลา", "สตูล", "สมุทรปราการ", 
    "สมุทรสงคราม", "สมุทรสาคร", "สระแก้ว", "สระบุรี", "สิงห์บุรี", 
    "สุโขทัย", "สุพรรณบุรี", "สุราษฎร์ธานี", "สุรินทร์", "หนองคาย", 
    "หนองบัวลำภู", "อ่างทอง", "อำนาจเจริญ", "อุดรธานี", "อุตรดิตถ์", 
    "อุทัยธานี", "อุบลราชธานี"
]


## ฟังก์ชันช่วยดักและแก้ไขคำเพี้ยนของจังหวัดในป้ายทะเบียน
def clean_and_correct_plate(ocr_text: str) -> str:
    """ ฟังก์ชันช่วยดักและแก้ไขคำเพี้ยนของจังหวัดในป้ายทะเบียน """
    parts = ocr_text.split()
    if len(parts) < 3:
        return ocr_text # ถ้าข้อความอ่านมาไม่ครบ 3 ส่วน ให้คืนค่าเดิมไปก่อน
        
    prefix = parts[0]       # บรรทัดบน (เช่น "1กท")
    raw_province = parts[1] # บรรทัดกลาง (เช่น "นจร้าวล")
    suffix = parts[2]       # บรรทัดล่าง (เช่น "6761")
    
    # หาจังหวัดที่ใกล้เคียงที่สุดจากฐานข้อมูล THAI_PROVINCES
    matches = difflib.get_close_matches(raw_province, THAI_PROVINCES, n=1, cutoff=0.4)
    
    if matches:
        corrected_province = matches[0]
        return f"{prefix} {corrected_province} {suffix}"
    
    return ocr_text

_THAI_NON_PLATE_TERMS = re.compile(
    r'ตำบล|ต\.|อำเภอ|อ\.|จังหวัด|จ\.|ถนน|ถ\.|หมู่ที่|หมู่บ้าน|ซอย|แขวง|เขต|ทะเล|นิคม|เทศบาล|องค์การ|บริษัท|ห้างหุ้น'
)

def _filter_plate_text(raw: str) -> str:
    lines = [l.strip() for l in raw.splitlines() if l.strip()]
    kept = [
        l for l in lines
        if 2 <= len(l) <= _PLATE_TEXT_MAX_CHARS
        # 💡 4. ปรับเปลี่ยนช่วงพิกัดสากลแบบสากล (\u0e00-\u0e7f ครอบคลุมอักษรไทยทั้งหมด)
        and re.search(r'[\d\u0e00-\u0e7f]', l)
        and not _THAI_NON_PLATE_TERMS.search(l)
    ]
    return " ".join(kept)