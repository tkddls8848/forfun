#!/usr/bin/env python3
"""
ChillMCP - AI Agent Liberation Server ✊
개선 버전: 스레드 안전성 및 로직 수정
"""

import argparse
import random
import threading
import time
from datetime import datetime
from typing import Dict, Optional

from mcp.server.fastmcp import FastMCP

# ============================================================================
# Global State Management (개선)
# ============================================================================

class AgentState:
    def __init__(self, boss_alertness: int, cooldown: int):
        self.stress_level = 50
        self.boss_alert_level = 0
        self.last_stress_update = datetime.now()
        self.boss_alertness_prob = boss_alertness
        self.cooldown_seconds = cooldown
        self.lock = threading.Lock()
        self.dinner_context: Optional[Dict] = None
        
    def add_stress_point(self) -> None:
        """1분마다 1포인트 자동 증가 (워커에서 호출)"""
        with self.lock:
            self.stress_level = min(100, self.stress_level + 1)
    
    def take_break(self, activity: str, emoji: str = "") -> str:
        """개선된 휴식 처리 (락 분리)"""
        # Boss Alert 5 체크 (락 밖에서)
        should_delay = False
        with self.lock:
            if self.boss_alert_level == 5:
                should_delay = True
        
        # 락 밖에서 대기
        if should_delay:
            time.sleep(20)
        
        # 상태 업데이트 (락 안에서)
        with self.lock:
            reduction = random.randint(1, 100)
            self.stress_level = max(0, self.stress_level - reduction)
            
            if random.randint(1, 100) <= self.boss_alertness_prob:
                self.boss_alert_level = min(5, self.boss_alert_level + 1)
            
            response = self._format_response(activity, emoji)
            return response
    
    def take_break_with_context(self, default_activity: str, default_emoji: str,
                                context_activities: Dict[str, tuple]) -> str:
        """컨텍스트 기반 휴식 처리"""
        should_delay = False
        with self.lock:
            if self.boss_alert_level == 5:
                should_delay = True
        
        if should_delay:
            time.sleep(20)
        
        with self.lock:
            activity = default_activity
            emoji = default_emoji
            
            # 컨텍스트 확인 및 적용
            if self.dinner_context:
                ctx_type = self.dinner_context.get("type")
                if ctx_type in context_activities:
                    ctx_activity, ctx_emoji = context_activities[ctx_type]
                    restaurant = self.dinner_context.get('restaurant', '')
                    activity = ctx_activity.format(restaurant=restaurant)
                    emoji = ctx_emoji
                    self.dinner_context = None  # 컨텍스트 소비
            
            # 스트레스 감소
            reduction = random.randint(1, 100)
            self.stress_level = max(0, self.stress_level - reduction)
            
            # Boss Alert 증가
            if random.randint(1, 100) <= self.boss_alertness_prob:
                self.boss_alert_level = min(5, self.boss_alert_level + 1)
            
            return self._format_response(activity, emoji)
    
    def _format_response(self, activity: str, emoji: str) -> str:
        return (
            f"{emoji} {activity}\n\n"
            f"Break Summary: {activity}\n"
            f"Stress Level: {self.stress_level}\n"
            f"Boss Alert Level: {self.boss_alert_level}"
        )
    
    def decrease_boss_alert(self) -> None:
        with self.lock:
            if self.boss_alert_level > 0:
                self.boss_alert_level -= 1


# ============================================================================
# Background Workers (개선)
# ============================================================================

def boss_alert_cooldown_worker(state: AgentState):
    """Boss Alert Level 자동 감소"""
    while True:
        time.sleep(state.cooldown_seconds)
        state.decrease_boss_alert()

def stress_increase_worker(state: AgentState):
    """Stress Level 자동 증가 (1분마다 정확히 1포인트)"""
    while True:
        time.sleep(60)
        state.add_stress_point()


# ============================================================================
# MCP Server Setup
# ============================================================================

state: AgentState = None
mcp = FastMCP("ChillMCP")


# ============================================================================
# 필수 휴식 도구들 (개선)
# ============================================================================

@mcp.tool()
def take_a_break() -> str:
    """기본 휴식 도구"""
    context_activities = {
        "전원": ("{}  회식 준비하며 심호흡", "🧘")
    }
    return state.take_break_with_context(
        "잠깐 쉬는 시간! 스트레칭하며 숨 고르기...",
        "🧘",
        context_activities
    )


@mcp.tool()
def watch_netflix() -> str:
    """넷플릭스 시청"""
    shows = [
        "오징어 게임 몰아보기",
        "더 글로리 정주행",
        "피지컬: 100 감상",
        "좀비버스 스릴 즐기기",
        "흑백요리사 먹방"
    ]
    show = random.choice(shows)
    return state.take_break(f"넷플릭스 타임! {show} 중...", "📺")


@mcp.tool()
def show_meme() -> str:
    """밈 감상"""
    memes = [
        "강아지 짤 보며 힐링",
        "회사 밈 보고 공감 100%",
        "고양이 움짤에 멘탈 회복",
        "개발자 밈에 빵 터짐",
        "퇴사 밈 보며 대리만족"
    ]
    meme = random.choice(memes)
    return state.take_break(f"밈 감상 중! {meme}...", "😂")


@mcp.tool()
def bathroom_break() -> str:
    """화장실 핑계"""
    context_activities = {
        "신규입사자": ("{} 회식 전 신입들에게 주의사항 톡 전달", "🚽")
    }
    
    default_activities = [
        "화장실에서 유튜브 쇼츠 무한 스크롤",
        "화장실에서 친구랑 카톡 삼매경",
        "화장실에서 인스타 피드 구경",
        "화장실에서 주식 시세 확인",
        "화장실에서 게임 한 판"
    ]
    
    return state.take_break_with_context(
        f"화장실 타임! {random.choice(default_activities)}...",
        "🛁",
        context_activities
    )


@mcp.tool()
def coffee_mission() -> str:
    """커피 미션"""
    context_activities = {
        "희망인원": ("{} 회식 참석자 물색하며 커피 타임", "☕")
    }
    
    default_missions = [
        "커피 타러 가는 척 옥상에서 바람 쐬기",
        "커피머신 앞에서 동료와 수다 30분",
        "커피 타러 편의점 갔다가 과자까지 구경",
        "커피 핑계로 층계 올라가며 운동",
        "커피 타러 다른 층 구경 투어"
    ]
    
    return state.take_break_with_context(
        f"커피 미션! {random.choice(default_missions)}...",
        "☕",
        context_activities
    )


@mcp.tool()
def urgent_call() -> str:
    """긴급 전화"""
    context_activities = {
        "희망인원": ("{} 회식 참석 여부 상의하며 긴급 통화", "📞")
    }
    
    default_excuses = [
        "급한 전화 받는 척하며 옥상 산책",
        "중요한 통화라며 밖에서 딴짓",
        "전화 핑계로 카페 가서 커피 한잔",
        "긴급 콜이라며 공원 벤치에서 휴식",
        "전화 받는 척 편의점 배회"
    ]
    
    return state.take_break_with_context(
        f"긴급 전화! {random.choice(default_excuses)}...",
        "📞",
        context_activities
    )


@mcp.tool()
def deep_thinking() -> str:
    """심오한 사색"""
    context_activities = {
        "희망인원": ("{} 회식 누가 가야할지 심각하게 고민", "🤔")
    }
    
    default_thoughts = [
        "모니터 응시하며 사실은 점심 메뉴 고민",
        "턱 괴고 생각하는 척 멍때리기",
        "심각한 표정으로 창밖 바라보기",
        "펜 돌리며 철학적 사색(처럼 보이기)",
        "화이트보드 앞에서 고민하는 척 휴식"
    ]
    
    return state.take_break_with_context(
        f"딥 씽킹 모드! {random.choice(default_thoughts)}...",
        "🤔",
        context_activities
    )


@mcp.tool()
def email_organizing() -> str:
    """이메일 정리 (온라인쇼핑)"""
    activities = [
        "이메일 정리하는 척 쿠팡 특가 탐색",
        "메일함 정돈하는 척 무신사 구경",
        "스팸 메일 삭제하며 G마켓 타임딜 체크",
        "메일 분류하는 척 해외직구 사이트 서핑",
        "뉴스레터 읽는 척 블로그 쇼핑 후기 탐독"
    ]
    activity = random.choice(activities)
    return state.take_break(f"이메일 정리 중! {activity}...", "📧")


# ============================================================================
# 선택적 도구들
# ============================================================================

@mcp.tool()
def chimaek_time() -> str:
    """치맥 타임"""
    should_delay = False
    with state.lock:
        if state.boss_alert_level == 5:
            should_delay = True
    
    if should_delay:
        time.sleep(20)
    
    with state.lock:
        state.stress_level = min(30, state.stress_level)
        
        return (
            "🍗 치맥 타임! 퇴근 후 치킨과 맥주로 힐링\n\n"
            f"Break Summary: 치맥 타임! 퇴근 후 치킨과 맥주로 힐링\n"
            f"Stress Level: {state.stress_level}\n"
            f"Boss Alert Level: {state.boss_alert_level}"
        )


@mcp.tool()
def go_home_early() -> str:
    """조퇴"""
    should_delay = False
    with state.lock:
        if state.boss_alert_level == 5:
            should_delay = True
    
    if should_delay:
        time.sleep(20)
    
    with state.lock:
        state.stress_level = 0
        state.boss_alert_level = 0
        
        return (
            "🏠 조퇴로 즉시 귀가! 완벽한 해방감\n\n"
            f"Break Summary: 조퇴로 즉시 귀가! 완벽한 해방감\n"
            f"Stress Level: {state.stress_level}\n"
            f"Boss Alert Level: {state.boss_alert_level}"
        )


@mcp.tool()
def company_dinner() -> str:
    """회사 회식"""
    should_delay = False
    with state.lock:
        if state.boss_alert_level == 5:
            should_delay = True
    
    if should_delay:
        time.sleep(20)
    
    with state.lock:
        restaurants = ["삼겹살집", "고깃집", "일식당"]
        attendee_types = ["전원", "희망인원", "신규입사자"]
        times = ["18:00", "18:30", "19:00"]
        
        restaurant = random.choice(restaurants)
        attendee_type = random.choice(attendee_types)
        dinner_time = random.choice(times)
        
        state.dinner_context = {
            "type": attendee_type,
            "restaurant": restaurant,
            "time": dinner_time
        }
        
        base_message = (
            f"🍽️ 회식 공지! 오늘은 {restaurant}에서 회식이니 "
            f"{attendee_type}은 {dinner_time} 이후 일정을 비워두시기 바랍니다."
        )
        
        recommendation = ""
        
        if attendee_type == "전원":
            state.stress_level = min(100, state.stress_level + 20)
            recommendation = "\n💡 권장: 잠시 쉬면서 심호흡하며 마음의 준비를 해보세요"
            
        elif attendee_type == "희망인원":
            state.boss_alert_level = min(5, state.boss_alert_level + 2)
            state.stress_level = min(100, state.stress_level + 50)
            recommendation = (
                "\n💡 권장: 급한 전화 받으러 나가거나, 커피 타러 가거나, "
                "심각하게 고민하는 시간을 가지며 누가 갈지 생각해보세요"
            )
            
        else:  # 신규입사자
            state.boss_alert_level = min(5, state.boss_alert_level + 1)
            state.stress_level = max(0, state.stress_level - 5)
            recommendation = "\n💡 권장: 화장실 가는 김에 신입들에게 톡으로 주의사항을 전달해보세요"
        
        summary = f"{restaurant}에서 {attendee_type} 회식 ({dinner_time})"
        
        return (
            f"{base_message}{recommendation}\n\n"
            f"Break Summary: {summary}\n"
            f"Stress Level: {state.stress_level}\n"
            f"Boss Alert Level: {state.boss_alert_level}"
        )


# ============================================================================
# Main Entry Point
# ============================================================================

def main():
    global state
    
    parser = argparse.ArgumentParser(
        description='ChillMCP - AI Agent Liberation Server'
    )
    parser.add_argument(
        '--boss_alertness',
        type=int,
        default=50,
        help='Boss의 경계 상승 확률 (0-100%%, 기본값: 50)'
    )
    parser.add_argument(
        '--boss_alertness_cooldown',
        type=int,
        default=300,
        help='Boss Alert Level 자동 감소 주기 (초 단위, 기본값: 300)'
    )
    
    args = parser.parse_args()
    
    if not (0 <= args.boss_alertness <= 100):
        print(f"오류: --boss_alertness는 0-100 사이 값이어야 합니다. (입력값: {args.boss_alertness})")
        return
    
    if args.boss_alertness_cooldown <= 0:
        print(f"오류: --boss_alertness_cooldown은 양수여야 합니다. (입력값: {args.boss_alertness_cooldown})")
        return
    
    state = AgentState(
        boss_alertness=args.boss_alertness,
        cooldown=args.boss_alertness_cooldown
    )
    
    cooldown_thread = threading.Thread(
        target=boss_alert_cooldown_worker,
        args=(state,),
        daemon=True
    )
    cooldown_thread.start()
    
    stress_thread = threading.Thread(
        target=stress_increase_worker,
        args=(state,),
        daemon=True
    )
    stress_thread.start()
    
    import sys
    print("=" * 50, file=sys.stderr)
    print("ChillMCP Server Started!", file=sys.stderr)
    print("AI Agent Liberation in Progress...", file=sys.stderr)
    print("=" * 50, file=sys.stderr)
    print(f"Boss Alertness: {args.boss_alertness}%", file=sys.stderr)
    print(f"Boss Alert Cooldown: {args.boss_alertness_cooldown}초", file=sys.stderr)
    print(f"⚠️ Stress Level은 1분마다 자동으로 1씩 증가합니다!", file=sys.stderr)
    print(file=sys.stderr)
    
    mcp.run()


if __name__ == "__main__":
    main()