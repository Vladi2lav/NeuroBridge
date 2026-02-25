import cv2
import numpy as np
import os
import mediapipe as mp
from sklearn.model_selection import train_test_split

os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import LSTM, Dense
from tensorflow.keras.utils import to_categorical

mp_hands = mp.solutions.hands
mp_drawing = mp.solutions.drawing_utils

# --- НАСТРОЙКИ ---
DATA_PATH = os.path.join(os.path.dirname(__file__), 'MP_Data')

# ТУТ ПИШИ СВОИ ЖЕСТЫ!
actions = np.array(['Привет', 'Да', 'Нет', 'Спасибо', 'Пока']) 

no_sequences = 30     # Количество "дублей" для каждого жеста
sequence_length = 30  # Количество кадров в "дубле" (примерно 1 секунда видео)

def prepare_folders():
    for action in actions:
        for sequence in range(no_sequences):
            try:
                os.makedirs(os.path.join(DATA_PATH, action, str(sequence)))
            except:
                pass

def extract_keypoints(results):
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
    return np.concatenate([lh, rh])

def collect_data():
    prepare_folders()
    cap = cv2.VideoCapture(0)
    with mp_hands.Hands(min_detection_confidence=0.5, min_tracking_confidence=0.5, max_num_hands=2) as hands:
        for action in actions:
            print(f"\n[ВНИМАНИЕ] Подготовьтесь показывать жест: {action}")
            cv2.waitKey(2000) 
            
            for sequence in range(no_sequences):
                for frame_num in range(sequence_length):
                    ret, frame = cap.read()
                    
                    if not ret:
                        continue

                    # MediaPipe процесс
                    image = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                    image.flags.writeable = False                  
                    results = hands.process(image)                 
                    image.flags.writeable = True                   
                    image = cv2.cvtColor(image, cv2.COLOR_RGB2BGR)

                    # Рисуем палочки и точки на руках
                    if results.multi_hand_landmarks:
                        for hand_landmarks in results.multi_hand_landmarks:
                            mp_drawing.draw_landmarks(
                                image, 
                                hand_landmarks, 
                                mp_hands.HAND_CONNECTIONS, 
                                mp_drawing.DrawingSpec(color=(121, 22, 76), thickness=2, circle_radius=4), 
                                mp_drawing.DrawingSpec(color=(250, 44, 250), thickness=2, circle_radius=2)
                            )
                    
                    # Инструкции на экране
                    if frame_num == 0: 
                        cv2.putText(image, 'НАЧАЛО ЗАПИСИ', (120,200), cv2.FONT_HERSHEY_SIMPLEX, 1, (0,255,0), 3)
                        cv2.putText(image, f'{action} | Дубль {sequence + 1}/{no_sequences}', (15, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (0,0,255), 2)
                        cv2.imshow('Сбор данных жестов', image)
                        cv2.waitKey(1500) # Даем паузу перед самим дублем руками!
                    else:
                        cv2.putText(image, f'{action} | Дубль {sequence + 1}/{no_sequences}', (15, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (0,0,255), 2)
                        cv2.imshow('Сбор данных жестов', image)
                    
                    keypoints = extract_keypoints(results)
                    npy_path = os.path.join(DATA_PATH, action, str(sequence), str(frame_num))
                    np.save(npy_path, keypoints)

                    if cv2.waitKey(10) & 0xFF == ord('q'):
                        print("Прервано пользователем.")
                        cap.release()
                        cv2.destroyAllWindows()
                        return

        cap.release()
        cv2.destroyAllWindows()
        print("\n[+] СБОР ДАННЫХ УСПЕШНО ОКОНЧЕН!")

def train_model():
    print("\n--- Загрузка данных для обучения ---")
    sequences, labels = [], []
    # Собираем только то, что удалось успешно отснять
    valid_actions = []
    
    for action in actions:
        action_has_data = False
        for sequence in range(no_sequences):
            window = []
            is_valid_sequence = True
            for frame_num in range(sequence_length):
                npy_path = os.path.join(DATA_PATH, action, str(sequence), f"{frame_num}.npy")
                if os.path.exists(npy_path):
                    res = np.load(npy_path)
                    window.append(res)
                else:
                    is_valid_sequence = False
                    break # Если не хватает кадров, пропускаем этот дубль
                    
            if is_valid_sequence:
                sequences.append(window)
                # Пока складируем оригинальные строки (Названия жестов) вместо индексов!
                labels.append(action)
                action_has_data = True
                
        if action_has_data:
            valid_actions.append(action)

    if len(sequences) == 0:
        print("\n[!] ОШИБКА: Нет записанных данных для обучения!")
        print("Пожалуйста, сначала запусти пункт 1 и запиши жесты на камеру.")
        return

    # Теперь создаем label_map ТОЛЬКО из тех жестов, для которых есть данные
    label_map = {label:num for num, label in enumerate(valid_actions)}
    
    # Превращаем текстовые метки в числа на основе новой карты
    numeric_labels = [label_map[label] for label in labels]

    print(f"\nДанные загружены. Найдено дублей: {len(sequences)}")
    print(f"Обучаемся на жестах: {valid_actions}")
    
    X = np.array(sequences)
    y = to_categorical(numeric_labels).astype(int)

    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.05)

    print("\n--- Сборка LSTM нейросети ---")
    model = Sequential()
    model.add(LSTM(64, return_sequences=True, activation='relu', input_shape=(sequence_length, 126)))
    model.add(LSTM(128, return_sequences=True, activation='relu'))
    model.add(LSTM(64, return_sequences=False, activation='relu'))
    model.add(Dense(64, activation='relu'))
    model.add(Dense(32, activation='relu'))
    # Выходной слой теперь равен КОЛИЧЕСТВУ СОБРАННЫХ жестов, а не всем 5 изначально заданным!
    model.add(Dense(len(valid_actions), activation='softmax'))

    model.compile(optimizer='Adam', loss='categorical_crossentropy', metrics=['categorical_accuracy'])

    print("\n--- Обучение модели ---")
    model.fit(X_train, y_train, epochs=120, callbacks=[])

    model_path = os.path.join(os.path.dirname(__file__), 'gesture_model.h5')
    model.save(model_path)
    
    # СОХРАНЯЕМ СПИСОК ЖЕСТОВ ДЛЯ СЕРВЕРА
    classes_path = os.path.join(os.path.dirname(__file__), 'gesture_classes.txt')
    with open(classes_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(valid_actions))
        
    print(f"\n[+] Модель успешно обучена и сохранена: {model_path}")

if __name__ == '__main__':
    print("="*50)
    print("🤖 АССИСТЕНТ ОБУЧЕНИЯ ЖЕСТОВ TENSORFLOW 🤖")
    print("="*50)
    print("1. Собрать данные камерой (Требуется вебка!)")
    print("2. Обучить модель на собранных данных")
    choice = input("\nВыберите действие (1 или 2): ")
    if choice == '1':
        print("\n=> Запуск камеры...")
        collect_data()
    elif choice == '2':
        train_model()
    else:
        print("Неверный выбор.")
