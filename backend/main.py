import asyncio
import base64
import json
import logging
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

import uvicorn
import cv2
import numpy as np
import mediapipe as mp
from concurrent.futures import ThreadPoolExecutor
import time
import math
import os

os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'
try:
    from tensorflow.keras.models import load_model
    gesture_model = load_model('gesture_model.h5')
    
    # Читаем реальные классы, на которых модель была обучена
    classes_path = 'gesture_classes.txt'
    if os.path.exists(classes_path):
        with open(classes_path, 'r', encoding='utf-8') as f:
            gesture_actions = np.array([line.strip() for line in f if line.strip()])
    else:
        # Если вдруг файла нет, падаем на запасной вариант
        gesture_actions = np.array(['Привет'])
        print("[-] gesture_classes.txt не найден! Субтитры могут быть неверными.")
        
    print(f"[+] Модель TensorFlow загружена! Жесты: {gesture_actions.tolist()}")
except Exception as e:
    gesture_model = None
    gesture_actions = []
    print(f"[-] Модель TensorFlow не найдена (распознавание отключено): {e}")

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)



# Initialize MediaPipe Hands
mp_hands = mp.solutions.hands
hands = mp_hands.Hands(
    static_image_mode=False,
    max_num_hands=2,
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5
)

# Для обработки тяжелой нейросети без блокировки асинхронного FastAPI
executor = ThreadPoolExecutor(max_workers=4)

def process_image_sync(img_rgb):
    return hands.process(img_rgb)

logger = logging.getLogger("api")

@app.get("/")
def read_root():
    return {"status": "NeuroERP Backend is running", "message": "Connection OK"}

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("Client connected to general WS")
    try:
        while True:
            data = await websocket.receive_text()
            print(f"Received msg: {data}")
            if data == "ping":
                await websocket.send_text("pong")
            else:
                await websocket.send_text(f"Echo: {data}")
    except WebSocketDisconnect:
        print("Client disconnected from general WS")

@app.websocket("/ws/hand_tracking")
async def hand_tracking_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("Client connected for Hand Tracking")

    clench_start_time = 0
    was_fist = False
    
    button_visible = False
    button_pos = None
    
    block_visible = False
    block_pos = None
    block_grabbed = False
    
    # LSTM Буфер
    sequence = []
    current_subtitle = ""

    try:
        while True:
            # Читаем сразу бинарные данные, без накладных расходов JSON и Base64
            # Заголовок: 1 байт (format), 4 байта (width), 4 байта (height), 4 байта (rotation) = 13 байт минимум
            data = await websocket.receive_bytes()
            print(f"📥 [СЕРВЕР] Получен кадр трекинга. Размер: {len(data)} байт")
            
            if len(data) < 16:
                print("⚠️ [СЕРВЕР] Игнор: пакет меньше 16 байт")
                continue

            # Парсим заголовок (16 байт)
            format_code = data[0]
            w = int.from_bytes(data[1:5], byteorder='little')
            h = int.from_bytes(data[5:9], byteorder='little')
            rotation = int.from_bytes(data[9:13], byteorder='little', signed=True)
            print(f"📋 [СЕРВЕР] Заголовок: format={format_code}, w={w}, h={h}, rot={rotation}")

            img_data = data[16:]
            img = None

            try:
                if format_code == 0: # NV21
                    if w > 0 and h > 0:
                        nparr = np.frombuffer(img_data, np.uint8).reshape((h + h // 2, w))
                        img = cv2.cvtColor(nparr, cv2.COLOR_YUV2BGR_NV21)
                elif format_code == 1: # BGRA8888
                    if w > 0 and h > 0:
                        nparr = np.frombuffer(img_data, np.uint8).reshape((h, w, 4))
                        img = cv2.cvtColor(nparr, cv2.COLOR_BGRA2BGR)
                elif format_code == 2: # RGBA8888 (Из Flutter RepaintBoundary)
                    if w > 0 and h > 0:
                        nparr = np.frombuffer(img_data, np.uint8)
                        expected_len = h * w * 4
                        if len(nparr) == expected_len:
                            nparr = nparr.reshape((h, w, 4))
                            img = cv2.cvtColor(nparr, cv2.COLOR_RGBA2BGR)
                            print("✅ [СЕРВЕР] Изображение RGBA успешно декодировано!")
                        else:
                            print(f"❌ [СЕРВЕР] Ошибка размерности RGBA! Ожидалось {expected_len}, пришло {len(nparr)}")
                            continue
                else:
                    nparr = np.frombuffer(img_data, np.uint8)
                    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

                if img is None:
                    print("❌ [СЕРВЕР] Не удалось декодировать img (None)")
                    continue

                # Rotate image if rotation is provided (MediaPipe expects upright images)
                if rotation == 90:
                    img = cv2.rotate(img, cv2.ROTATE_90_CLOCKWISE)
                elif rotation == 180:
                    img = cv2.rotate(img, cv2.ROTATE_180)
                elif rotation == 270:
                    img = cv2.rotate(img, cv2.ROTATE_90_COUNTERCLOCKWISE)

                # Convert BGR to RGB
                img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
                
                # Запускаем MediaPipe в пуле потоков, чтобы он НЕ блочил asyncio event loop!
                loop = asyncio.get_event_loop()
                results = await loop.run_in_executor(executor, process_image_sync, img_rgb)
                print("✅ [СЕРВЕР] MediaPipe обработал кадр!")
            except Exception as e:
                print(f"🚨 [СЕРВЕР] Ошибка обработки кадра (OpenCV -> MediaPipe): {e}")
                continue

            hand_landmarks_list = []
            if results.multi_hand_landmarks:
                print(f"✋ [СЕРВЕР] Найдено рук: {len(results.multi_hand_landmarks)}")
                for idx, hand_landmarks in enumerate(results.multi_hand_landmarks):
                    landmarks = []
                    for lm in hand_landmarks.landmark:
                        landmarks.append({
                            "x": lm.x,
                            "y": lm.y,
                            "z": lm.z
                        })
                    hand_landmarks_list.append(landmarks)
            # else:
                print("🔍 [СЕРВЕР] Руки не найдены в этом кадре.")

            # Virtual elements logic
            if hand_landmarks_list:
                lm = hand_landmarks_list[0] # use the first detected hand
                
                # Check fist state
                currently_fist = True
                for tip, mcp in [(8, 5), (12, 9), (16, 13), (20, 17)]:
                    dist_tip = math.hypot(lm[tip]['x'] - lm[0]['x'], lm[tip]['y'] - lm[0]['y'])
                    dist_mcp = math.hypot(lm[mcp]['x'] - lm[0]['x'], lm[mcp]['y'] - lm[0]['y'])
                    if dist_tip > dist_mcp:  # finger is extended
                        currently_fist = False
                        break
                
                current_time = time.time()
                
                # Clench / unclench tracking
                if currently_fist and not was_fist:
                    clench_start_time = current_time
                elif not currently_fist and was_fist:
                    if clench_start_time > 0 and (current_time - clench_start_time) < 0.5:
                        # Spawn button at palm center
                        button_visible = True
                        button_pos = {"x": lm[9]['x'], "y": lm[9]['y']}
                        block_visible = False
                        block_grabbed = False
                
                was_fist = currently_fist
                
                # Button interaction (press with index finger tip)
                if button_visible and button_pos:
                    idx_tip = lm[8]
                    dist_to_btn = math.hypot(idx_tip['x'] - button_pos['x'], idx_tip['y'] - button_pos['y'])
                    if dist_to_btn < 0.05:  # radius of button
                        button_visible = False
                        block_visible = True
                        block_pos = {"x": button_pos['x'], "y": button_pos['y']}
                
                # Block interaction (drag with pinch)
                if block_visible and block_pos:
                    thumb_tip = lm[4]
                    idx_tip = lm[8]
                    pinch_dist = math.hypot(thumb_tip['x'] - idx_tip['x'], thumb_tip['y'] - idx_tip['y'])
                    pinch_point = {"x": (thumb_tip['x'] + idx_tip['x']) / 2, "y": (thumb_tip['y'] + idx_tip['y']) / 2}
                    
                    if pinch_dist < 0.05:  # is pinching
                        if block_grabbed:
                            block_pos = pinch_point # move
                        else:
                            dist_to_block = math.hypot(pinch_point['x'] - block_pos['x'], pinch_point['y'] - block_pos['y'])
                            if dist_to_block < 0.1:  # grab radius
                                block_grabbed = True
                                block_pos = pinch_point
                    else:
                        block_grabbed = False

            # --- ИНТЕГРАЦИЯ НЕЙРОСЕТИ (LSTM) ---
            lh = np.zeros(21*3)
            rh = np.zeros(21*3)
            if results.multi_hand_landmarks:
                for idx, hand_landmarks in enumerate(results.multi_hand_landmarks):
                    handedness = results.multi_handedness[idx].classification[0].label
                    res = np.array([[lm.x, lm.y, lm.z] for lm in hand_landmarks.landmark]).flatten()
                    if handedness == 'Left':
                        lh = res
                    else:
                        rh = res
            keypoints = np.concatenate([lh, rh])
            
            sequence.append(keypoints)
            sequence = sequence[-30:] # Храним только последние 30 кадров (окно в ~1 сек)
            
            if len(sequence) == 30 and gesture_model is not None:
                # Если в кадре есть хоть какие-то точки
                if np.sum(sequence) > 0:
                    try:
                        # Делаем быстрый предикт прямо тут. Для батча = 1 он мгновенный
                        res_pred = gesture_model.predict(np.expand_dims(sequence, axis=0), verbose=0)[0]
                        best_idx = np.argmax(res_pred)
                        
                        # Если нейронка уверена на 85%
                        if res_pred[best_idx] > 0.85: 
                            current_subtitle = str(gesture_actions[best_idx])
                    except Exception as e:
                        pass
                else:
                    # Рук нет, можно скрыть субтитр
                    pass

            await websocket.send_json({
                "type": "hands_data",
                "hands": hand_landmarks_list,
                "subtitle": current_subtitle,
                "virtual_elements": {
                    "button": {"visible": button_visible, "pos": button_pos},
                    "block": {"visible": block_visible, "pos": block_pos, "grabbed": block_grabbed}
                }
            })
            print("📤 [СЕРВЕР] Отправлен JSON с координатами обратно на клиент.")

    except WebSocketDisconnect:
        print("❌ [СЕРВЕР] Клиент отключился от Hand Tracking")
    except Exception as e:
        print(f"🚨 [СЕРВЕР] Глобальная ошибка вебсокета Hand Tracking: {e}")

import uuid
from typing import Dict, Any

# In-memory dictionary to store Websocket connections for WebRTC signaling
# rooms[room_id][client_id] = WebSocket
rooms: Dict[str, Dict[str, WebSocket]] = {}

@app.websocket("/ws/signal/{room_id}")
async def signaling_endpoint(websocket: WebSocket, room_id: str):
    await websocket.accept()
    if room_id not in rooms:
        rooms[room_id] = {}
        
    client_id = str(uuid.uuid4())
    rooms[room_id][client_id] = websocket
    print(f"[WS] + User {client_id} CONNECTED to room {room_id}. Total users in room: {len(rooms[room_id])}")
    
    # Send the user their ID and the list of others
    other_peers = [pid for pid in rooms[room_id].keys() if pid != client_id]
    await websocket.send_json({"type": "room_state", "my_id": client_id, "peers": other_peers})
    
    # Notify others that this peer joined
    for pid, client_ws in list(rooms[room_id].items()):
        if pid != client_id:
            await client_ws.send_json({"type": "peer_joined", "peer_id": client_id})
    
    try:
        while True:
            data = await websocket.receive_text()
            try:
                msg = json.loads(data)
                target_id = msg.get("to")
                # Ensure the message has a "from" assigned by the server for security
                msg["from"] = client_id
                
                # Targeted sending
                if target_id and target_id in rooms[room_id]:
                    await rooms[room_id][target_id].send_text(json.dumps(msg))
                else:
                    # Generic broadcast
                    for pid, client_ws in list(rooms[room_id].items()):
                        if pid != client_id:
                            await client_ws.send_text(json.dumps(msg))
            except json.JSONDecodeError:
                pass
    except WebSocketDisconnect:
        if client_id in rooms.get(room_id, {}):
            del rooms[room_id][client_id]
        if not rooms[room_id]:
            del rooms[room_id]
        else:
            for pid, client_ws in list(rooms[room_id].items()):
                try:
                    await client_ws.send_json({"type": "peer_left", "peer_id": client_id})
                except:
                    pass
        print(f"[WS] - User {client_id} DISCONNECTED from room {room_id}. Remaining: {len(rooms.get(room_id, {}))}")
    except Exception as e:
        print(f"[WS] ! ERROR in room {room_id}: {str(e)}")
        if room_id in rooms and client_id in rooms[room_id]:
            del rooms[room_id][client_id]

import socket
import os
import shutil
from fastapi import File, UploadFile, Form, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

class MaterialGenRequest(BaseModel):
    title: str
    description: str

@app.post("/api/rooms/{room_id}/materials/upload")
async def upload_material(room_id: str, file: UploadFile = File(...)):
    room_dir = os.path.join("materials", room_id)
    os.makedirs(room_dir, exist_ok=True)
    file_path = os.path.join(room_dir, file.filename)
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    return {"status": "success", "filename": file.filename}

@app.post("/api/rooms/{room_id}/materials/generate")
async def generate_material(room_id: str, req: MaterialGenRequest):
    room_dir = os.path.join("materials", room_id)
    os.makedirs(room_dir, exist_ok=True)
    content = f"Лекция: {req.title}\n\nОписание: {req.description}\n\nЗначительный объем текста, представляющий собой лекционный материал.\n(Нейросеть генерирует и сохраняет здесь результаты: лекция успешно создана.)"
    safe_filename = "".join([c for c in req.title if c.isalpha() or c.isdigit() or c==' ']).rstrip() or "generated"
    filename = f"{safe_filename}.txt"
    file_path = os.path.join(room_dir, filename)
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
    return {"status": "success", "filename": filename}

@app.get("/api/rooms/{room_id}/materials")
def list_materials(room_id: str):
    room_dir = os.path.join("materials", room_id)
    if not os.path.exists(room_dir):
        return {"materials": []}
    files = os.listdir(room_dir)
    return {"materials": files}

@app.get("/api/rooms/{room_id}/materials/{filename}")
def download_material(room_id: str, filename: str):
    file_path = os.path.join("materials", room_id, filename)
    if os.path.exists(file_path):
        return FileResponse(path=file_path, filename=filename)
    raise HTTPException(status_code=404, detail="File not found")

def get_local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # doesn't even have to be reachable
        s.connect(('10.255.255.255', 1))
        IP = s.getsockname()[0]
    except Exception:
        IP = '127.0.0.1'
    finally:
        s.close()
    return IP

@app.get("/api/rooms/available")
def get_available_room():
    i = 1
    while True:
        room_id = str(i)
        if room_id not in rooms or len(rooms[room_id]) == 0:
            return {"room_id": room_id}
        i += 1

if __name__ == "__main__":
    ip = get_local_ip()
    port = 8001
    print("\n" + "="*50)
    print("🚀 NEURO ERP BACKEND IS STARTING 🚀")
    print("="*50)
    print(f"✅ ВВЕДИТЕ ЭТОТ АДРЕС В ТЕЛЕФОНЕ: {ip}:{port}")
    print("="*50 + "\n")
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=False)
